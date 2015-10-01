module Percy
  module Capybara
    class Client
      module Builds
        def current_build(options = {})
          return if !enabled?  # Silently skip if the client is disabled.
          @current_build ||= client.create_build(client.config.repo, options)
          @current_build
        end
        alias_method :initialize_build, :current_build

        def upload_missing_build_resources(build_resources)
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

        def build_initialized?
          !!@current_build
        end

        def finalize_current_build
          return if !enabled?  # Silently skip if the client is disabled.
          if !build_initialized?
            raise Percy::Capybara::Client::BuildNotInitializedError.new(
              'Failed to finalize build because no build has been initialized.')
          end
          client.finalize_build(current_build['data']['id'])
        end
      end
    end
  end
end
