require 'percy/capybara/client/builds'
require 'percy/capybara/client/snapshots'
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

      def initialize(options = {})
        @client = options[:client] || Percy.client
        @enabled = options[:enabled]

        if defined?(Rails)
          @sprockets_environment = options[:sprockets_environment] || Rails.application.assets
          @sprockets_options = options[:sprockets_options] || Rails.application.config.assets
        end
      end

      def enabled?
        return @enabled if !@enabled.nil?

        # Enable if PERCY_ENABLE=1 in local dev (allow disabling if 0).
        return @enabled ||= ENV['PERCY_ENABLE'] == '1' if ENV['PERCY_ENABLE']

        # If in supported CI environment.
        @enabled ||= !Percy::Client::Environment.current_ci.nil?
      end

      def rescue_connection_failures(&block)
        raise ArgumentError.new('block is requried') if !block_given?
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
        if sprockets_environment && sprockets_options
          Percy.logger.debug { 'Using sprockets_loader to discover assets.' }
          options[:sprockets_environment] = sprockets_environment
          options[:sprockets_options] = sprockets_options
          Percy::Capybara::Loaders::SprocketsLoader.new(options)
        else
          Percy.logger.debug { 'Using native_loader to discover assets (slower).' }
          Percy::Capybara::Loaders::NativeLoader.new(options)
        end
      end
    end
  end
end
