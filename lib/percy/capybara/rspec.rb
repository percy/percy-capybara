require 'percy/capybara/client/builds'
require 'percy/capybara/client/snapshots'
require 'percy/capybara/loaders/native_loader'
require 'percy/capybara/loaders/sprockets_loader'

module Percy
  module Capybara
    module RSpec
      before(:each) { Percy::Capybara.initialize_build }
    end
  end
end
