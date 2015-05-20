require 'percy/capybara/client/builds'
require 'percy/capybara/client/snapshots'

module Percy
  module Capybara
    class Client
      include Percy::Capybara::Client::Builds
      include Percy::Capybara::Client::Snapshots

      class Error < Exception; end
      class BuildNotInitializedError < Error; end

      attr_reader :client

      def initialize(options = {})
        @client = options[:client] || Percy.client
      end
    end
  end
end
