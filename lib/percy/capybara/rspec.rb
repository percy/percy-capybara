require 'rspec/core'

# TODO: this has been deprecated for a long time, remove this file when releasing v3.0.0.

RSpec.configure do |config|
  config.before(:suite) { Percy::Capybara.initialize_build }
  config.after(:suite) { Percy::Capybara.finalize_build }
end
