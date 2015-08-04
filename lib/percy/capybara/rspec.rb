require 'rspec/core'

RSpec.configure do |config|
  config.after(:suite) { Percy::Capybara.finalize_build }
end
