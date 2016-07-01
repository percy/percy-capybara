module Percy
  module Capybara
    module Loaders
      # Hybrid between SprocketsLoader and NativeLoader, in order to capture iframes data.
      class SprocketsWithIframesLoader < SprocketsLoader
        def snapshot_resources
          resources = super

          _get_iframes_data.each do |iframe_data|
            content = iframe_data['content']
            sha = Digest::SHA256.hexdigest(content)

            resources <<
              Percy::Client::Resource.new(
                iframe_data['url'],
                sha: sha,
                content: content,
                mimetype: 'text/html'
              )
          end

          resources
        end

        # NOTES:
        # - Potentially slow
        # - Requires the test to be run with `js: true`
        # - Doesn't handle several different iframes with the same URL (`src` attribute)
        def _get_iframes_data
          # Do a fast search for iframes in the page, before calling slow `_evaluate_script`
          return [] unless page.body.include?('<iframe ')

          # Get frames URLs and full HTML content, via javascript
          script = <<-JS.strip.gsub(/\n+|\s+/, ' ')
            (function () {
              var data = [];
              var tags = document.getElementsByTagName('iframe');
              var el;

              for (var i = 0; i < tags.length; i++) {
                el = tags[i];
                data.push({
                  'url': el.attributes['src'].value,
                  'content': el.contentWindow.document.getElementsByTagName('html')[0].outerHTML
                });
              }

              return JSON.stringify(data);
            })()
          JS

          # Execute and convert JS to get iframes data
          JSON(page.evaluate_script(script))
        end
      end
    end
  end
end
