# This must be required & started before any app code (for proper coverage)
require 'simplecov'
SimpleCov.start
SimpleCov.minimum_coverage 100

require 'capybara/rspec'
require 'webmock/rspec'
require 'percy'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4.
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  # config.warnings = true

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  # Setting this allows you to use `--seed` to deterministically reproduce
  # test failures related to randomization by passing the same `--seed` value
  # as the one that triggered the failure.
  Kernel.srand config.seed

  # See https://github.com/teamcapybara/capybara#selecting-the-driver for other options
  Capybara.default_driver = :selenium_headless
  Capybara.javascript_driver = :selenium_headless

  # Setup for Capybara to test Jekyll static files served by Rack
  Capybara.server_port = 3003
  Capybara.server = :puma, { Silent: true }
  Capybara.app = Rack::File.new(File.join(File.dirname(__FILE__), 'fixture'))
end
