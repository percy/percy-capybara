require 'percy/capybara/client/builds'
require 'percy/capybara/client/snapshots'
require 'percy/capybara/client/user_agent'
require 'percy/capybara/loaders/filesystem_loader'
require 'percy/capybara/loaders/native_loader'
require 'percy/capybara/loaders/sprockets_loader'
require 'percy/capybara/loaders/ember_cli_rails_loader'

module Percy
  module Capybara
    class Client
      include Percy::Capybara::Client::Builds
      include Percy::Capybara::Client::Snapshots
      include Percy::Capybara::Client::UserAgent

      class Error < RuntimeError; end
      class BuildNotInitializedError < Error; end
      class WebMockBlockingConnectionsError < Error; end

      attr_reader :client

      attr_accessor :sprockets_environment
      attr_accessor :sprockets_options
      attr_accessor :loader
      attr_accessor :loader_options

      def initialize(options = {})
        @failed = false

        @enabled = options[:enabled]
        @loader_options = options[:loader_options] || {}
        @loader = options[:loader]

        @client = options[:client] || \
          Percy.client(client_info: _client_info, environment_info: _environment_info)

        return unless defined?(Rails) && defined?(Sprockets::Rails)

        @sprockets_environment = options[:sprockets_environment] || Rails.application.assets
        @sprockets_options = options[:sprockets_options] || Rails.application.config.assets
      end

      # Check that environment variables required for Percy::Client are set
      def required_environment_variables_set?
        !!ENV['PERCY_TOKEN']
      end

      def enabled?
        return @enabled unless @enabled.nil?

        # Disable if PERCY_ENABLE is set to 0
        return @enabled = false if ENV['PERCY_ENABLE'] == '0'

        # Enable if required environment variables are set
        return @enabled = true if required_environment_variables_set?

        # Disable otherwise
        @enabled = false
      end

      def disable!
        @enabled = false
      end

      def rescue_connection_failures
        raise ArgumentError, 'block is required' unless block_given?
        begin
          yield
        rescue Percy::Client::ServerError, # Rescue server errors.
               Percy::Client::PaymentRequiredError, # Rescue quota exceeded errors.
               Percy::Client::ConnectionFailed, # Rescue some networking errors.
               Percy::Client::TimeoutError => e
          Percy.logger.error(e)
          @enabled = false
          @failed = true
          nil
        end
      end

      def failed?
        !!@failed
      end

      def initialize_loader(options = {})
        merged_options = loader_options.merge(options)

        is_sprockets = sprockets_environment && sprockets_options

        if is_sprockets
          merged_options[:sprockets_environment] = sprockets_environment
          merged_options[:sprockets_options]     = sprockets_options
        end

        if loader
          case loader
          when :filesystem
            Percy.logger.debug { 'Using filesystem_loader to discover assets.' }
            Percy::Capybara::Loaders::FilesystemLoader.new(merged_options)
          when :native
            Percy.logger.debug { 'Using native_loader to discover assets (slow).' }
            Percy::Capybara::Loaders::NativeLoader.new(merged_options)
          when :ember_cli_rails
            Percy.logger.debug { 'Using ember_cli_rails_loader to discover assets.' }
            mounted_apps = merged_options.delete(:mounted_apps)
            Percy::Capybara::Loaders::EmberCliRailsLoader.new(mounted_apps, merged_options)
          else
            Percy.logger.debug { 'Using a custom loader to discover assets.' }
            loader.new(merged_options)
          end
        elsif is_sprockets
          Percy.logger.debug { 'Using sprockets_loader to discover assets.' }
          Percy::Capybara::Loaders::SprocketsLoader.new(merged_options)
        else
          unless @warned_about_native_loader
            Percy.logger.warn \
              '[DEPRECATED] The native_loader is deprecated and will be opt-in in a future ' \
              'release. You should move to the faster, more reliable filesystem_loader. See the ' \
              'docs for Non-Rails frameworks: https://percy.io/docs/clients/ruby/capybara '
            @warned_about_native_loader = true
          end
          Percy.logger.debug { 'Using native_loader to discover assets (slower).' }
          Percy::Capybara::Loaders::NativeLoader.new(merged_options)
        end
      end
    end
  end
end
