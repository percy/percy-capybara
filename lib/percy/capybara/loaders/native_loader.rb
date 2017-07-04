require 'percy/capybara/loaders/base_loader'
require 'digest'
require 'uri'

module Percy
  module Capybara
    module Loaders
      # Resource loader that uses the native Capybara browser interface to discover resources.
      # This loader uses JavaScript to discover page resources, so specs must be tagged with
      # "js: true" because the default Rack::Test driver does not support executing JavaScript.
      class NativeLoader < BaseLoader
        PATH_REGEX = /\A\/[^\\s\"']*/
        DATA_URL_REGEX = /\Adata:/
        LOCAL_HOSTNAMES = [
          'localhost',
          '127.0.0.1',
          '0.0.0.0',
        ].freeze

        def initialize(options = {})
          super(options)

          @asset_hostnames = options[:asset_hostnames] || []
          @assets_from_stylesheets = options[:include_assets_from_stylesheets] || :all
          @assets_from_stylesheets = ->(_) { true } if @assets_from_stylesheets == :all
        end

        def snapshot_resources
          resources = []
          resources << root_html_resource
          resources += _get_css_resources
          resources += _get_image_resources
          resources += iframes_resources
          resources
        end

        def build_resources
          []
        end

        # @private
        def _get_css_resources
          resources = []
          # Find all CSS resources.
          # http://www.quirksmode.org/dom/w3c_css.html#access
          script = <<-JS
            function findStylesRecursively(stylesheet, css_urls) {
              if (stylesheet.href) {  // Skip stylesheet without hrefs (inline stylesheets).
                css_urls.push(stylesheet.href);

                // Remote stylesheet rules cannot be accessed because of the same-origin policy.
                // Unfortunately, if you touch .cssRules in Selenium, it throws a JavascriptError
                // with 'The operation is insecure'. To work around this, skip reading rules of
                // remote stylesheets but still include them for fetching.
                //
                // TODO: If a remote stylesheet has an @import, it will be missing because we don't
                // notice it here. We could potentially recursively fetch remote imports in
                // ruby-land below.
                var parser = document.createElement('a');
                parser.href = stylesheet.href;
                if (parser.host != window.location.host) {
                  return;
                }
              }
              for (var i = 0; i < stylesheet.cssRules.length; i++) {
                var rule = stylesheet.cssRules[i];
                // Depth-first search, handle recursive @imports.
                if (rule.styleSheet) {
                  findStylesRecursively(rule.styleSheet, css_urls);
                }
              }
            }

            var css_urls = [];
            for (var i = 0; i < document.styleSheets.length; i++) {
              findStylesRecursively(document.styleSheets[i], css_urls);
            }
            return css_urls;
          JS
          resource_urls = _evaluate_script(page, script)
          urls_referred_by_css = []

          resource_urls.each do |url|
            next unless _should_include_url?(url)
            response = _fetch_resource_url(url)
            urls_referred_by_css.concat(_parse_urls_from_css(response.body))
            _absolute_url_to_relative!(url, _current_host_port)
            next unless response
            resources << Percy::Client::Resource.new(
              url, mimetype: 'text/css', content: response.body,
            )
          end
          @urls_referred_by_css = urls_referred_by_css
          resources
        end
        private :_get_css_resources

        # @private
        def _get_image_resources
          resources = []
          image_urls = Set.new

          # Find all image tags on the page.
          page.all('img').each do |image_element|
            srcs = []
            srcs << image_element[:src] unless image_element[:src].nil?

            srcset_raw_urls = image_element[:srcset] || ''
            temp_urls = srcset_raw_urls.split(',')
            temp_urls.each do |temp_url|
              srcs << temp_url.split(' ').first
            end

            srcs.each do |url|
              image_urls << url
            end
          end

          raw_image_urls = _evaluate_script(page, _find_all_css_loaded_background_image_js)
          raw_image_urls.each do |raw_image_url|
            temp_urls = raw_image_url.scan(/url\(["']?(.*?)["']?\)/)
            # background-image can accept multiple url()s, so temp_urls is an array of URLs.
            temp_urls.each do |temp_url|
              url = temp_url[0]
              image_urls << url
            end
          end

          if @assets_from_stylesheets && @assets_from_stylesheets != :none
            image_urls.merge(@urls_referred_by_css.select { |path| @assets_from_stylesheets[path] })
          end

          image_urls.each do |image_url|
            # If url references are blank, browsers will often fill them with the current page's
            # URL, which makes no sense and will never be renderable. Strip these.
            next if image_url == current_path \
              || image_url == page.current_url \
              || image_url.strip.empty?

            # Make the resource URL absolute to the current page. If it is already absolute, this
            # will have no effect.
            resource_url = URI.join(page.current_url, image_url).to_s

            # Skip duplicates.
            next if resources.find { |r| r.resource_url == resource_url }

            next unless _should_include_url?(resource_url)

            # Fetch the images.
            # TODO(fotinakis): this can be pretty inefficient for image-heavy pages because the
            # browser has already loaded them once and this fetch cannot easily leverage the
            # browser's cache. However, often these images are probably local resources served by a
            # development server, so it may not be so bad. Re-evaluate if this becomes an issue.
            response = _fetch_resource_url(resource_url)
            _absolute_url_to_relative!(resource_url, _current_host_port)
            next unless response

            resources << Percy::Client::Resource.new(
              resource_url, mimetype: response.content_type, content: response.body,
            )
          end
          resources
        end
        private :_get_image_resources

        # @private
        def _find_all_css_loaded_background_image_js
          <<-JS
            var raw_image_urls = [];

            var tags = document.getElementsByTagName('*');
            var el;
            var rawValue;

            for (var i = 0; i < tags.length; i++) {
              el = tags[i];
              if (el.currentStyle) {
                rawValue = el.currentStyle['backgroundImage'];
              } else if (window.getComputedStyle) {
                rawValue = window.getComputedStyle(el).getPropertyValue('background-image');
              }
              if (!rawValue || rawValue === "none") {
                continue;
              } else {
                raw_image_urls.push(rawValue);
              }
            }
            return raw_image_urls;
          JS
        end

        # @private
        def _parse_urls_from_css(css_content)
          css_content.scan(/url\(([^\)]+)\)/)
            .map { |i| _remove_quotes(i.first) }
            .select { |path| _should_include_url?(path) }
            .map { |path| _remove_hash_from_url(path) }
        end

        # @private
        def _remove_hash_from_url(string)
          if /^(?<url_base>.+)?\#[^#]+$/ =~ string
            if url_base.end_with?('?')
              url_base[0...-1]
            else
              url_base
            end
          else
            string
          end
        end

        # @private
        def _remove_quotes(string)
          if string.length >= 2 && (string[0] == string[-1]) && ['"', "'"].include?(string[0])
            string[1...-1]
          else
            string
          end
        end

        # @private
        def _fetch_resource_url(url)
          response = Percy::Capybara::HttpFetcher.fetch(url)
          unless response
            STDERR.puts '[percy] Warning: failed to fetch page resource, ' \
              "this might be a bug: #{url}"
            return nil
          end
          response
        end
        private :_fetch_resource_url

        # @private
        def _evaluate_script(page, script)
          script = <<-JS
            (function() {
              #{script}
            })();
          JS
          page.evaluate_script(script)
        end
        private :_evaluate_script

        # @private
        def _should_include_url?(url)
          # It is a URL or a path, but not a data URI.
          url_match = URL_REGEX.match(url)
          data_url_match = DATA_URL_REGEX.match(url)
          result = (url_match || PATH_REGEX.match(url)) && !data_url_match

          # Is not a remote URL.
          if url_match && !data_url_match
            host = url_match[2]
            result = asset_hostnames.include?(host) || _same_server?(url, _current_host_port)
          end

          !!result
        end

        # @private
        def _current_host_port
          url_match = URL_REGEX.match(page.current_url)
          url_match[1] + url_match[2] + (url_match[3] || '')
        end
        private :_current_host_port

        # @private
        def _same_server?(url, host_port)
          url.start_with?(host_port + '/') || url == host_port
        end
        private :_same_server?

        # @private
        def _absolute_url_to_relative!(url, host_port)
          url.gsub!(host_port + '/', '/') if url.start_with?(host_port + '/')
        end
        private :_absolute_url_to_relative!

        def asset_hostnames
          LOCAL_HOSTNAMES + @asset_hostnames
        end
        private :asset_hostnames
      end
    end
  end
end
