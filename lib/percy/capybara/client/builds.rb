module Percy
  module Capybara
    class Client
      module Builds
        def initialize_build(options = {})
          return if !enabled?  # Silently skip if the client is disabled.
          return @current_build if build_initialized?

          # Gather build resources to upload with build.
          start = Time.now
          build_resources = options[:build_resources] || initialize_loader.build_resources
          options[:resources] = build_resources if !build_resources.empty?

          # Extra debug info.
          build_resources.each { |br| Percy.logger.debug { "Build resource: #{br.resource_url}" } }
          Percy.logger.debug { "All build resources loaded (#{Time.now - start}s)" }

          rescue_connection_failures do
            @current_build = client.create_build(client.config.repo, options)
            _upload_missing_build_resources(build_resources) if !build_resources.empty?
          end
          if failed?
            Percy.logger.error { "Percy build failed! Check log above for errors." }
            return
          end
          @current_build
        end

        def current_build
          return if !enabled?  # Silently skip if the client is disabled.
          @current_build
        end

        def build_initialized?
          !!@current_build
        end

        def finalize_current_build
          return if !enabled?  # Silently skip if the client is disabled.
          if !build_initialized?
            raise Percy::Capybara::Client::BuildNotInitializedError.new(
              'Failed to finalize build because no build has been initialized.')
          end
          result = rescue_connection_failures do
            client.finalize_build(current_build['data']['id'])
          end
          if failed?
            Percy.logger.error { "Percy build failed! Check log above for errors." }
            return
          end
          result
        end

        # @private
        def _upload_missing_build_resources(build_resources)
          # Upload any missing build resources.
          new_build_resources = current_build['data'] &&
            current_build['data']['relationships'] &&
            current_build['data']['relationships']['missing-resources'] &&
            current_build['data']['relationships']['missing-resources']['data']
          return 0 if !new_build_resources

          new_build_resources.each_with_index do |missing_resource, i|
            sha = missing_resource['id']
            resource = build_resources.find { |r| r.sha == sha }
            content = resource.content || File.read(resource.path)
            client.upload_resource(current_build['data']['id'], content)
            if i % 50 == 0
              puts "[percy] Uploading #{i+1} of #{new_build_resources.length} new resources..."
            end
          end
          new_build_resources.length
        end
        private :_upload_missing_build_resources
      end
    end
  end
end
