require 'socket'
require 'timeout'
require 'sprockets'

module TestHelpers
  class ServerDown < Exception; end

  def get_random_open_port
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
    root = File.expand_path("../../lib/percy/capybara/client/testdata", __FILE__)
    environment = Sprockets::Environment.new(root)
    environment.append_path '.'

    sprockets_options = double('sprockets_options')
    allow(sprockets_options).to receive(:precompile).and_return([/(?:\/|\\|\A)base\.(css|js)$/])
    allow(sprockets_options).to receive(:digest).and_return(false)

    capybara_client.sprockets_environment = environment
    capybara_client.sprockets_options = sprockets_options
  end
end