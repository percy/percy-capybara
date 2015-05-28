require 'percy/capybara/client/builds'
require 'percy/capybara/client/snapshots'

module Percy
  module Capybara
    class Client
      include Percy::Capybara::Client::Builds
      include Percy::Capybara::Client::Snapshots

      class Error < Exception; end
      class BuildNotInitializedError < Error; end
      class WebMockBlockingConnectionsError < Error; end

      attr_reader :client

      def initialize(options = {})
        @client = options[:client] || Percy.client
        @enabled = options[:enabled]
      end

      def enabled?
        # Only enable if in supported CI environment or local dev with PERCY_ENABLE=1.
        @enabled ||= !Percy::Client::Environment.current_ci.nil? || ENV['PERCY_ENABLE'] == '1'
      end
    end
  end
end
