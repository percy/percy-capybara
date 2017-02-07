require 'percy/capybara/client/builds'
require 'percy/capybara/client/snapshots'
require 'percy/capybara/loaders/filesystem_loader'
require 'percy/capybara/loaders/native_loader'
require 'percy/capybara/loaders/sprockets_loader'

module Percy
  module Capybara
    class Client
      include Percy::Capybara::Client::Builds
      include Percy::Capybara::Client::Snapshots

      class Error < Exception; end
      class BuildNotInitializedError < Error; end
      class WebMockBlockingConnectionsError < Error; end

      attr_reader :client

      attr_accessor :sprockets_environment
      attr_accessor :sprockets_options
      attr_accessor :loader
      attr_accessor :loader_options

      def initialize(options = {})
        @failed = false

        @client = options[:client] || Percy.client
        @enabled = options[:enabled]

        @loader_options = {}

        if defined?(Rails)
          @sprockets_environment = options[:sprockets_environment] || Rails.application.assets
          @sprockets_options = options[:sprockets_options] || Rails.application.config.assets
        end
      end

      # Check that environment variables required for Percy::Client are set
      def required_environment_variables_set?
        if !ENV['PERCY_TOKEN'].nil? && ENV['PERCY_PROJECT'].nil?
          raise RuntimeError.new(
            '[percy] It looks like you were trying to enable Percy because PERCY_TOKEN is set, ' +
            'but you are missing the PERCY_PROJECT environment variable!'
          )
        end

        !(ENV['PERCY_PROJECT'].nil? || ENV['PERCY_TOKEN'].nil?)
      end

      def enabled?
        return @enabled if !@enabled.nil?

        # Disable if PERCY_ENABLE is set to 0
        return @enabled = false if ENV['PERCY_ENABLE'] == '0'

        # Enable if required environment variables are set
        return @enabled = true if required_environment_variables_set?

        # Disable otherwise
        return @enabled = false
      end

      def disable!
        @enabled = false
      end

      def rescue_connection_failures(&block)
        raise ArgumentError.new('block is required') if !block_given?
        begin
          block.call
        rescue Percy::Client::ServerError,  # Rescue server errors.
            Percy::Client::PaymentRequiredError,  # Rescue quota exceeded errors.
            Percy::Client::ConnectionFailed,  # Rescue some networking errors.
            Percy::Client::TimeoutError => e
          Percy.logger.error(e)
          @enabled = false
          @failed = true
          nil
        end
      end

      def failed?
        return !!@failed
      end

      def initialize_loader(options = {})
        merged_options = loader_options.merge(options)
        if loader
          case loader
          when :filesystem
            Percy.logger.debug { 'Using filesystem_loader to discover assets.' }
            Percy::Capybara::Loaders::FilesystemLoader.new(merged_options)
          when :native
            Percy.logger.debug { 'Using native_loader to discover assets (slower).' }
            Percy::Capybara::Loaders::NativeLoader.new(merged_options)
          else
            Percy.logger.debug { 'Using a custom loader to discover assets.' }
            loader.new(merged_options)
          end
        elsif sprockets_environment && sprockets_options
          Percy.logger.debug { 'Using sprockets_loader to discover assets.' }
          merged_options[:sprockets_environment] = sprockets_environment
          merged_options[:sprockets_options] = sprockets_options
          Percy::Capybara::Loaders::SprocketsLoader.new(merged_options)
        else
          Percy.logger.debug { 'Using native_loader to discover assets (slower).' }
          Percy::Capybara::Loaders::NativeLoader.new(merged_options)
        end
      end
    end
  end
end
