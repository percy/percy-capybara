require 'capybara/rspec'
require 'capybara/webkit'
require 'webmock/rspec'
require 'support/test_helpers'
require 'percy'
require 'percy/capybara'

Capybara::Webkit.configure do |config|
  # config.allow_url("*")
  config.block_unknown_urls
end

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

  # Comment this out to test the default Selenium/Firefox flow:
  Capybara.javascript_driver = :webkit

  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
  config.before(:each, type: :feature) do
    WebMock.disable_net_connect!(allow_localhost: true, allow: [/i.imgur.com/])
  end

  # Cover all debug messages by outputting them in this gem's tests.
  Percy.config.debug = true

  # Start a temp webserver that serves the testdata directory.
  # You can test this server manually by running:
  # ruby -run -e httpd spec/lib/percy/capybara/client/testdata/ -p 9090
  config.before(:all, type: :feature) do
    port = get_random_open_port
    Capybara.app = nil
    Capybara.app_host = "http://localhost:#{port}"
    Capybara.run_server = false

    # Note: using this form of popen to keep stdout and stderr silent and captured.
    dir = File.expand_path('../lib/percy/capybara/client/testdata/', __FILE__)
    @process = IO.popen([
      'ruby', '-run', '-e', 'httpd', dir, '-p', port.to_s, err: [:child, :out]
    ].flatten)

    # Block until the server is up.
    WebMock.disable_net_connect!(allow_localhost: true)
    verify_server_up(Capybara.app_host)
  end
  config.after(:all, type: :feature) { Process.kill('INT', @process.pid) }
end
