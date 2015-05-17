require 'digest'

module Percy
  class Capybara
    module Snapshots
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

      def _find_resources(page)
        resource_map = {}

        # Main HTML resource.
        script = <<-JS
          var htmlElement = document.getElementsByTagName('html')[0];
          return htmlElement.outerHTML;
        JS
        html = _evaluate_script(page, script)
        sha = Digest::SHA256.hexdigest(html)
        resource_url = page.current_url
        resource_map[sha] = Percy::Client::Resource.new(
          sha, resource_url, is_root: true, mimetype: 'text/html', content: html)

        # ...

        resource_map
      end
      private :_find_resources

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
