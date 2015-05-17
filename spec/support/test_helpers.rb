module TestHelpers
  def get_random_open_port
    # Using a port of "0" relies on the system to pick an open port.
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end
end