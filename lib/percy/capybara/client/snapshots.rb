require 'set'
require 'faraday'
require 'httpclient'
require 'digest'
require 'uri'
require 'time'
require 'pathname'

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

          name = options[:name]
          loader = initialize_loader(page: page)

          Percy.logger.debug { "Snapshot started (name: #{name.inspect})" }

          # If this is the first snapshot, create the build and upload build resources.
          # DEPRECATED: this flow is for the pre-parallel world.
          if !build_initialized?
            Percy.logger.warn do
              "DEPRECATED: percy-capybara will remove implicitly created builds. You should " +
              "update your usage to call initialize_build explicitly at the start of a test " +
              "suite, or to use the Percy RSpec setup to do it for you."
            end

            start = Time.now
            build_resources = loader.build_resources
            if Percy.config.debug
              build_resources.each do |build_resource|
                Percy.logger.debug { "Build resource: #{build_resource.resource_url}" }
              end
            end
            Percy.logger.debug { "All build resources loaded (#{Time.now - start}s)" }
            initialize_build(resources: build_resources)
            _upload_missing_build_resources(build_resources)
          end

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
            snapshot = client.create_snapshot(current_build_id, resources, name: name)
            snapshot['data']['relationships']['missing-resources']['data'].each do |missing_resource|
              sha = missing_resource['id']
              client.upload_resource(current_build_id, resource_map[sha].content)
            end
            Percy.logger.debug { "All snapshot resources uploaded (#{Time.now - start}s)" }

            # Finalize the snapshot.
            client.finalize_snapshot(snapshot['data']['id'])
          end
          if failed?
            Percy.logger.error { "Build failed due to connection errors." }
            return
          end
          true
        end
      end
    end
  end
end
