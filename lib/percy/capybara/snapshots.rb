require 'digest'

module Percy
  class Capybara
    module Snapshots
      def snapshot(page, options = {})
        name = options[:name]
        current_build_id = current_build['data']['id']
        resources = _find_resources(page)
        client.create_snapshot(build['data']['id'], resources, name: name)
      end

      def _find_resources(page)
        resources = []

        # Main HTML resource.
        script = <<-JS
          var htmlElement = document.getElementsByTagName('html')[0];
          return htmlElement.outerHTML;
        JS
        html = _evaluate_script(page, script)
        sha = Digest::SHA256.hexdigest(html)
        resource_url = page.current_url
        resources << Percy::Client::Resource.new(
          sha, resource_url, is_root: true, mimetype: 'text/html', content: html)

        # ...

        resources
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
