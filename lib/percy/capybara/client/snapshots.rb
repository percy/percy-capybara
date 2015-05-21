require 'set'
require 'faraday'
require 'httpclient'
require 'digest'

module Percy
  module Capybara
    class Client
      module Snapshots
        # @private
        FETCH_SENTINEL_VALUE = '[[FETCH]]'

        # Takes a snapshot of the given page HTML and its assets.
        #
        # @param [Capybara::Session] page The Capybara page to snapshot.
        # @param [Hash] options
        # @option options [String] :name A unique name for the current page that identifies it across
        #   builds. By default this is the URL of the page, but can be customized if the URL does not
        #   entirely identify the current state.
        def snapshot(page, options = {})
          name = options[:name]
          current_build_id = current_build['data']['id']
          resource_map = _find_resources(page)
          snapshot = client.create_snapshot(current_build_id, resource_map.values, name: name)

          # Upload the content for any missing resources.
          snapshot['data']['links']['missing-resources']['linkage'].each do |missing_resource|
            sha = missing_resource['id']
            client.upload_resource(current_build_id, resource_map[sha].content)
          end
        end

        # @private
        def _find_resources(page)
          resource_map = {}
          resources = []
          resources << _get_root_html_resource(page)
          resources += _get_css_resources(page)
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
          sha = Digest::SHA256.hexdigest(html)
          resource_url = page.current_url
          Percy::Client::Resource.new(
            sha, resource_url, is_root: true, mimetype: 'text/html', content: html)
        end
        private :_get_root_html_resource

        # @private
        def _get_css_resources(page)
          resources = []
          # Find all CSS resources.
          # http://www.quirksmode.org/dom/w3c_css.html#access
          script = <<-JS
            function findStylesRecursively(stylesheet, result_data) {
              result_data = result_data || {};
              if (stylesheet.href) {
                result_data[stylesheet.href] = result_data[stylesheet.href] || '';

                // Remote stylesheet rules cannot be accessed because of the same-origin policy.
                // Unfortunately, if you touch .cssRules in Selenium, it throws a JavascriptError
                // with 'The operation is insecure'. To work around this, skip any remote stylesheets
                // and mark them with a sentinel value so we can fetch them later.
                var parser = document.createElement('a');
                parser.href = stylesheet.href;
                if (parser.host != window.location.host) {
                  result_data[stylesheet.href] = '#{FETCH_SENTINEL_VALUE}'; // Must be a string.
                  return;
                }
              }

              for (var i = 0; i < stylesheet.cssRules.length; i++) {
                var rule = stylesheet.cssRules[i];
                // Skip stylesheet without hrefs (inline stylesheets).
                // These will be present in the HTML snapshot.
                if (stylesheet.href) {
                  // Append current rule text.
                  result_data[stylesheet.href] += rule.cssText + '\\n';
                }

                // Handle recursive @imports.
                if (rule.styleSheet) {
                  findStylesRecursively(rule.styleSheet, result_data);
                }
              }
            }

            var percy_resources = {};
            for (var i = 0; i < document.styleSheets.length; i++) {
              findStylesRecursively(document.styleSheets[i], percy_resources);
            }
            return percy_resources;
          JS

          # Returned datastructure: {"<absolute URL>" => "<CSS text>", ...}
          resource_data = _evaluate_script(page, script)

          resource_data.each do |resource_url, css|
            if css == FETCH_SENTINEL_VALUE
              # Handle sentinel value that indicates a remote CSS resource that must be fetched.
              response = _fetch_resource_url(resource_url)
              next if !response
              css = response.body
            end

            sha = Digest::SHA256.hexdigest(css)
            resources << Percy::Client::Resource.new(
              sha, resource_url, mimetype: 'text/css', content: css)
          end
          resources
        end
        private :_get_css_resources

        # @private
        def _get_image_resources(page)
          resources = []
          image_urls = Set.new

          # TODO: support for srcsets.

          # Find all image tags on the page.
          page.all('img').each do |image_element|
            if !image_element[:src].nil?
              src = image_element[:src]
              # Skip data URIs.
              next if src.match(/\Adata:/)
              image_urls << src
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
            if !temp_urls.empty?
              # background-image can accept multiple url()s, so temp_urls is an array of URLs.
              temp_urls.each do |temp_url|
                # Skip data URIs.
                next if temp_url[0].match(/\Adata:/)
                image_urls << temp_url[0]
              end
            end
          end

          image_urls.each do |image_url|
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
              sha, resource_url, mimetype: response.headers['Content-Type'], content: response.body)
          end
          resources
        end
        private :_get_image_resources

        # @private
        def _fetch_resource_url(url)
          begin
            response = Faraday.get(url)
          rescue Exception => e
            if defined?(WebMock) && e.is_a?(WebMock::NetConnectNotAllowedError)
              raise Percy::Capybara::Client::WebMockBlockingConnectionsError.new(
                "It looks like you're using WebMock! That's great, but in order to use\n" +
                "Percy::Capybara you need to let connections through WebMock. For example:\n" +
                "\n" +
                "config.before(:each, type: :feature) { WebMock.allow_net_connect! }\n"
              )
            end
          end
          content = response.body
          if response.status != 200
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
