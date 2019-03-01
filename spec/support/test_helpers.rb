require 'net/http'

module TestHelpers
  class ServerDown < RuntimeError; end

  def random_open_port
    # Using a port of "0" relies on the system to pick an open port.
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  def verify_server_up(host, port)
    4.times do
      begin
        Net::HTTP.get(host, '/', port)
        return true
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL
        sleep 0.5
      end
    end
    raise ServerDown, "Server failed to start: #{host}:#{port}"
  end
end
