require 'percy/client'
require 'percy/capybara/version'
require 'percy/capybara/snapshots'

module Percy
  class Capybara
    include Percy::Capybara::Snapshots

    attr_accessor :client

    def initialize(options = {})
      @client = options[:client] || Percy.client
      @repo_slug = options[:repo_slug] || Percy.current_local_repo
    end

    def current_build
      @current_build ||= client.create_build(@repo_slug)
    end
  end
end
