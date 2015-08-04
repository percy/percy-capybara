require 'percy'
require 'percy/capybara/version'
require 'percy/capybara/httpfetcher'
require 'percy/capybara/client'

module Percy
  module Capybara
    # @see Percy::Capybara::Client
    def self.capybara_client
      @capybara_client ||= Percy::Capybara::Client.new
    end

    # {include:Percy::Capybara::Client::Snapshots#snapshot}
    # @param (see Percy::Capybara::Client::Snapshots#snapshot)
    # @option (see Percy::Capybara::Client::Snapshots#snapshot)
    # @see Percy::Capybara::Client::Snapshots#snapshot
    def self.snapshot(page, options = {})
      capybara_client.snapshot(page, options)
    end

    # Creates a new build.
    #
    # This usually does not need to be called explictly because the build is automatically created
    # the first time a snapshot is created. However, this method might be useful in situations like
    # multi-process tests where a single build must be created before forking.
    #
    # @see Percy::Capybara::Client::Builds#initialize_build
    def self.initialize_build(options = {})
      capybara_client.initialize_build(options)
    end

    # Finalize the current build.
    #
    # This must be called to indicate that the build is complete after all snapshots have been
    # taken. It will silently return if no build or snapshots were created.
    #
    # @see Percy::Capybara::Client::Builds#finalize_current_build
    def self.finalize_build
      return if !capybara_client.build_initialized?
      capybara_client.finalize_current_build
    end

    # Reset the global Percy::Capybara module state.
    def self.reset
      @capybara_client = nil
    end
  end
end
