module Percy
  module Capybara
    class Client
      def _client_info
        "percy-capybara/#{VERSION}"
      end

      def _environment_info
        [
          _loader_name,
          _rails_version,
          _sinatra_version,
          _ember_cli_rails_version,
        ].compact.join('; ')
      end

      def _loader_name
        "percy-capybara-loader/#{loader}" if loader
      end

      def _ember_cli_rails_version
        "ember-cli-rails/#{EmberCli::VERSION}" if defined? EmberCli
      end

      def _rails_version
        "rails/#{Rails.version}" if defined? Rails
      end

      def _sinatra_version
        "sinatra/#{Sinatra::VERSION}" if defined? Sinatra
      end
    end
  end
end
