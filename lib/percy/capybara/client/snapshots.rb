require 'set'
require 'faraday'
require 'httpclient'
require 'digest'
require 'uri'
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

          # If this is the first snapshot, create the build and upload build resources.
          if !build_initialized?
            build_resources = loader.build_resources
            initialize_build(resources: build_resources)
            upload_missing_build_resources(build_resources)
          end

          current_build_id = current_build['data']['id']
          resources = loader.snapshot_resources
          resource_map = {}
          resources.each { |r| resource_map[r.sha] = r }

          # Create the snapshot and upload any missing snapshot resources.
          snapshot = client.create_snapshot(current_build_id, resources, name: name)
          snapshot['data']['relationships']['missing-resources']['data'].each do |missing_resource|
            sha = missing_resource['id']
            client.upload_resource(current_build_id, resource_map[sha].content)
          end

          # Finalize the snapshot.
          client.finalize_snapshot(snapshot['data']['id'])

          true
        end
      end
    end
  end
end
