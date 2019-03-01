require 'capybara/rspec'
require 'support/test_helpers'
require 'percy/capybara'
require 'selenium-webdriver'

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

  # See https://github.com/teamcapybara/capybara#selecting-the-driver for other options
  Capybara.default_driver = :selenium_chrome_headless
  Capybara.javascript_driver = :selenium_chrome_headless

  # Start a temp webserver that serves the test_data directory.
  # You can test this server manually by running:
  # ruby -run -e httpd spec/lib/percy/capybara/client/test_data/ -p 9090
  config.before(:all, type: :feature) do
    port = random_open_port
    Capybara.app = nil
    Capybara.app_host = "http://localhost:#{port}"
    Capybara.run_server = false

    # Note: using this form of popen to keep stdout and stderr silent and captured.
    dir = File.expand_path('../lib/percy/capybara/client/test_data/', __FILE__)
    @process = IO.popen(
      [
        'ruby', '-run', '-e', 'httpd', dir, '-p', port.to_s, err: [:child, :out],
      ].flatten,
    )

    # Block until the server is up.
    verify_server_up('localhost', port)
  end
  config.after(:all, type: :feature) { Process.kill('INT', @process.pid) }
end
