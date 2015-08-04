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
        # Only enable if in supported CI environment or local dev with PERCY_ENABLE=1.
        @enabled ||= !Percy::Client::Environment.current_ci.nil? || ENV['PERCY_ENABLE'] == '1'
      end

      def initialize_loader(options = {})
        if sprockets_environment && sprockets_options
          options[:sprockets_environment] = sprockets_environment
          options[:sprockets_options] = sprockets_options
          Percy::Capybara::Loaders::SprocketsLoader.new(options)
        else
          Percy::Capybara::Loaders::NativeLoader.new(options)
        end
      end
    end
  end
end
