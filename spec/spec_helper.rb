require 'capybara/rspec'
require 'capybara/webkit'
require 'webmock/rspec'
require 'support/test_helpers'
require 'percy'
require 'percy/capybara'

RSpec.configure do |config|
  config.include TestHelpers

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

  Capybara.javascript_driver = :webkit

  config.before(:all) do
    WebMock.disable_net_connect!(allow_localhost: true, allow: [/maxcdn.bootstrapcdn.com/])
  end
end
