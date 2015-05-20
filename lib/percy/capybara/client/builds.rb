module Percy
  module Capybara
    class Client
      module Builds
        def current_build
          @current_build ||= client.create_build(client.config.repo)
        end
        alias_method :initialize_build, :current_build

        def build_initialized?
          !!@current_build
        end

        def finalize_current_build
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
