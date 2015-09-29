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

        def snapshot_resources
          resources = []
          resources << root_html_resource
          resources += _get_css_resources
          resources += _get_image_resources
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

          resource_urls.each do |url|
            next if !_should_include_url?(url)
            response = _fetch_resource_url(url)
            next if !response
            sha = Digest::SHA256.hexdigest(response.body)
            resources << Percy::Client::Resource.new(
              url, mimetype: 'text/css', content: response.body)
          end
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
            srcs << image_element[:src] if !image_element[:src].nil?

            srcset_raw_urls = image_element[:srcset] || ''
            temp_urls = srcset_raw_urls.split(',')
            temp_urls.each do |temp_url|
              srcs << temp_url.split(' ').first
            end

            srcs.each do |url|
              image_urls << url
            end
          end

          # Find all CSS-loaded images which set a background-image.
          script = <<-JS
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
          raw_image_urls = _evaluate_script(page, script)
          raw_image_urls.each do |raw_image_url|
            temp_urls = raw_image_url.scan(/url\(["']?(.*?)["']?\)/)
            # background-image can accept multiple url()s, so temp_urls is an array of URLs.
            temp_urls.each do |temp_url|
              url = temp_url[0]
              image_urls << url
            end
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

            next if !_should_include_url?(resource_url)

            # Fetch the images.
            # TODO(fotinakis): this can be pretty inefficient for image-heavy pages because the
            # browser has already loaded them once and this fetch cannot easily leverage the
            # browser's cache. However, often these images are probably local resources served by a
            # development server, so it may not be so bad. Re-evaluate if this becomes an issue.
            response = _fetch_resource_url(resource_url)
            next if !response

            sha = Digest::SHA256.hexdigest(response.body)
            resources << Percy::Client::Resource.new(
              resource_url, mimetype: response.content_type, content: response.body)
          end
          resources
        end
        private :_get_image_resources

        # @private
        def _fetch_resource_url(url)
          response = Percy::Capybara::HttpFetcher.fetch(url)
          if !response
            STDERR.puts "[percy] Warning: failed to fetch page resource, this might be a bug: #{url}"
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
            result = LOCAL_HOSTNAMES.include?(host)
          end

          !!result
        end
      end
    end
  end
end
