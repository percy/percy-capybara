require 'socket'
require 'timeout'

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
    4.times do |_|
      begin
        http.get(host)
        return true
      rescue Errno::ECONNREFUSED
        sleep 0.5
      end
    end
    raise ServerDown, "Server failed to start: #{host}"
  end
end