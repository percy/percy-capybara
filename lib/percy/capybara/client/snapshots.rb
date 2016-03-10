require 'time'

module Percy
  module Capybara
    class Client
      module Snapshots
        # Takes a snapshot of the given page HTML and its assets.
        #
        # @param [Capybara::Session] page The Capybara page to snapshot.
        # @param [Hash] options
        # @option options [String] :name A unique name for the current page that identifies it across
        #   builds. By default this is the URL of the page, but can be customized if the URL does not
        #   entirely identify the current state.
        def snapshot(page, options = {})
          return if !enabled?  # Silently skip if the client is disabled.

          loader = initialize_loader(page: page)

          Percy.logger.debug { "Snapshot started (name: #{options[:name].inspect})" }
          start = Time.now
          current_build_id = current_build['data']['id']
          resources = loader.snapshot_resources
          resource_map = {}
          resources.each do |r|
            resource_map[r.sha] = r
            Percy.logger.debug { "Snapshot resource: #{r.resource_url}" }
          end
          Percy.logger.debug { "All snapshot resources loaded (#{Time.now - start}s)" }

          # Create the snapshot and upload any missing snapshot resources.
          start = Time.now
          rescue_connection_failures do
            snapshot = client.create_snapshot(current_build_id, resources, options)
            snapshot['data']['relationships']['missing-resources']['data'].each do |missing_resource|
              sha = missing_resource['id']
              client.upload_resource(current_build_id, resource_map[sha].content)
            end
            Percy.logger.debug { "All snapshot resources uploaded (#{Time.now - start}s)" }

            # Finalize the snapshot.
            client.finalize_snapshot(snapshot['data']['id'])
          end
          if failed?
            Percy.logger.error { "Percy build failed! Check log above for errors." }
            return
          end
          true
        end
      end
    end
  end
end
