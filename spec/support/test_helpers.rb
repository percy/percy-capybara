require 'socket'
require 'timeout'
require 'sprockets'

module TestHelpers
  class ServerDown < RuntimeError; end

  def random_open_port
    # Using a port of "0" relies on the system to pick an open port.
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  def verify_server_up(host)
    http = HTTPClient.new
    4.times do
      begin
        http.get(host)
        return true
      rescue Errno::ECONNREFUSED
        sleep 0.5
      end
    end
    raise ServerDown, "Server failed to start: #{host}"
  end

  def find_resource(resources, regex)
    begin
      resources.select { |resource| resource.resource_url.match(regex) }.fetch(0)
    rescue IndexError
      raise "Missing expected image with resource_url that matches: #{regex}"
    end
  end

  def setup_sprockets(capybara_client)
    root = File.expand_path('../../lib/percy/capybara/client/test_data', __FILE__)
    environment = Sprockets::Environment.new(root)
    environment.append_path '.'

    sprockets_options = double('sprockets_options')
    allow(sprockets_options).to receive(:precompile).and_return([%r{(?:/|\\|\A)base\.(css|js)$}])
    allow(sprockets_options).to receive(:digest).and_return(false)

    capybara_client.sprockets_environment = environment
    capybara_client.sprockets_options = sprockets_options
  end

  # Set the environment variables required by Percy::Client
  def set_required_env_variables
    ENV['PERCY_TOKEN'] = 'aa'
    ENV['PERCY_PROJECT'] = 'aa'
  end

  # Clear the environment variables required by Percy::Client
  def clear_percy_env_variables
    ENV.delete('PERCY_TOKEN')
    ENV.delete('PERCY_PROJECT')
    ENV.delete('PERCY_ENABLE')
  end
end
