require 'percy/capybara'
require 'capybara/poltergeist'

module Percy
  module Capybara
    # Simple block runner for self-contained Capybara tests.
    #
    # Requires:
    #   - poltergeist gem (which requires phantomjs)
    # Usage:
    #   Percy::Capybara::Anywhere.run(SERVER, ASSETS_DIR, ASSETS_BASE_URL) do |page|
    #     page.visit('/')
    #     Percy::Capybara.snapshot(page, name: 'main page')
    #   end
    module Anywhere
      def self.run(server, assets_dir, assets_base_url = nil)
        if ENV['PERCY_TOKEN'].nil?
          raise 'Whoops! You need to setup the PERCY_TOKEN environment variable.'
        end

        ::Capybara.run_server = false
        ::Capybara.app_host = server
        page = ::Capybara::Session.new(:poltergeist)

        Percy::Capybara.use_loader(:filesystem, assets_dir: assets_dir, base_url: assets_base_url)
        build = Percy::Capybara.initialize_build

        yield(page)

        Percy::Capybara.finalize_build
        puts
        puts 'Done! Percy snapshots are now processing...'
        puts "--> #{build['data']['attributes']['web-url']}"
      end
    end
  end
end
