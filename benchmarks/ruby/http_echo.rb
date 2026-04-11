# HTTP echo server benchmark — respond with fixed JSON
# Measure with: wrk -t2 -c100 -d5s http://localhost:8080/
require 'socket'

RESPONSE = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 27\r\nConnection: keep-alive\r\n\r\n{\"status\":\"ok\",\"count\":42}"

$stderr.puts "Ruby http_echo listening on :8080"
server = TCPServer.new("0.0.0.0", 8080)
loop do
  client = server.accept
  client.recv(4096)
  client.write(RESPONSE)
  client.close
end
