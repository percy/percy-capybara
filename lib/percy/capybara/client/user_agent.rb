module Percy
  module Capybara
    class Client
      module UserAgent
        def _client_info
          "percy-capybara/#{VERSION}"
        end

        def _environment_info
          [
            "percy-capybara-loader/#{loader}",
            "rails/#{_rails_version}",
            "sinatra/#{_sinatra_version}",
            "ember-cli-rails/#{_ember_cli_rails_version}",
          ].reject do |info|
            info =~ /\/$/ # reject if version is empty
          end.join('; ')
        end

        def _ember_cli_rails_version
          return unless defined? EmberCli

          require 'ember_cli/version'
          EmberCli::VERSION
        end

        def _rails_version
          Rails.version if defined? Rails
        end

        def _sinatra_version
          Sinatra::VERSION if defined? Sinatra
        end
      end
    end
  end
end
