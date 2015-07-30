require 'set'
require 'faraday'
require 'httpclient'
require 'digest'

module Percy
  module Capybara
    class Client
      module Snapshots
        # Modified version of Diego Perini's URL regex. https://gist.github.com/dperini/729294
        URL_REGEX = Regexp.new(
          # protocol identifier
          "(?:(?:https?:)?//)" +
          "(?:" +
            # IP address exclusion
            # private & local networks
            "(?!(?:10|127)(?:\\.\\d{1,3}){3})" +
            "(?!(?:169\\.254|192\\.168)(?:\\.\\d{1,3}){2})" +
            "(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})" +
            # IP address dotted notation octets
            # excludes loopback network 0.0.0.0
            # excludes reserved space >= 224.0.0.0
            # excludes network & broacast addresses
            # (first & last IP address of each class)
            "(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])" +
            "(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}" +
            "(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))" +
          "|" +
            # host name
            "(?:(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)" +
            # domain name
            "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]-*)*[a-z\\u00a1-\\uffff0-9]+)*" +
            # TLD identifier
            "(?:\\.(?:[a-z\\u00a1-\\uffff]{2,}))" +
          ")" +
          # port number
          "(?::\\d{2,5})?" +
          # resource path
          "(?:/[^\\s\"']*)?"
        )
        PATH_REGEX = /\/[^\\s\"']*/
        DATA_URL_REGEX = /\Adata:/

        # Takes a snapshot of the given page HTML and its assets.
        #
        # @param [Capybara::Session] page The Capybara page to snapshot.
        # @param [Hash] options
        # @option options [String] :name A unique name for the current page that identifies it across
        #   builds. By default this is the URL of the page, but can be customized if the URL does not
        #   entirely identify the current state.
        def snapshot(page, options = {})
          return if !enabled?  # Silently skip if the client is disabled.
          name = options[:name]
          current_build_id = current_build['data']['id']
          resource_map = _find_resources(page)
          snapshot = client.create_snapshot(current_build_id, resource_map.values, name: name)

          # Upload the content for any missing resources.
          snapshot['data']['relationships']['missing-resources']['data'].each do |missing_resource|
            sha = missing_resource['id']
            client.upload_resource(current_build_id, resource_map[sha].content)
          end

          # Finalize the snapshot.
          client.finalize_snapshot(snapshot['data']['id'])

          true
        end

        # @private
        def _find_resources(page)
          resource_map = {}
          resources = []
          resources << _get_root_html_resource(page)
          resources += _get_css_resources(page)
          resources += _get_image_resources(page)
          resources.each { |resource| resource_map[resource.sha] = resource }
          resource_map
        end
        private :_find_resources

        # @private
        def _get_root_html_resource(page)
          # Primary HTML.
          script = <<-JS
            var htmlElement = document.getElementsByTagName('html')[0];
            return htmlElement.outerHTML;
          JS
          html = _evaluate_script(page, script)
          resource_url = page.current_url
          Percy::Client::Resource.new(
            resource_url, is_root: true, mimetype: 'text/html', content: html)
        end
        private :_get_root_html_resource

        # @private
        def _get_css_resources(page)
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
            next if !_is_valid_url?(url)
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
        def _get_image_resources(page)
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
            next if !_is_valid_url?(image_url)

            # If url references are blank, browsers will often fill them with the current page's
            # URL, which makes no sense and will never be renderable. Strip these.
            next if image_url == page.current_url

            # Make the resource URL absolute to the current page. If it is already absolute, this
            # will have no effect.
            resource_url = URI.join(page.current_url, image_url).to_s

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
        def _is_valid_url?(url)
          # It is a URL or a path, but not a data URI.
          (URL_REGEX.match(url) || PATH_REGEX.match(url)) && !DATA_URL_REGEX.match(url)
        end

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
      end
    end
  end
end
