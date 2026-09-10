require 'socket'
require 'json'
require 'net/http'
require 'uri'

PORT = Integer(ENV['PORT'] || 8084)

if ARGV.include?('--health')
  begin
    uri = URI.parse("http://127.0.0.1:#{PORT}/healthz")
    response = Net::HTTP.get_response(uri)
    exit(response.code.to_i == 200 ? 0 : 1)
  rescue StandardError
    exit(1)
  end
end

server = TCPServer.new('0.0.0.0', PORT)
STDOUT.puts "Notification service listening on port #{PORT}"
STDOUT.flush

loop do
  Thread.start(server.accept) do |client|
    request_line = client.gets
    next unless request_line

    method, path, = request_line.split
    headers = {}

    while (line = client.gets) && (line != "\r\n")
      parts = line.split(': ', 2)
      headers[parts[0].downcase] = parts[1].strip if parts.size == 2
    end

    body = ''
    if headers['content-length']
      length = headers['content-length'].to_i
      body = client.read(length)
    end

    if method == 'GET' && path == '/healthz'
      resp_body = JSON.generate({ status: 'healthy', service: 'notification' })
      client.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: application/json\r\n" \
                   "Content-Length: #{resp_body.bytesize}\r\n" \
                   "Connection: close\r\n\r\n"
      client.print resp_body
    elsif method == 'POST' && path == '/notify'
      resp_body = JSON.generate({ status: 'acknowledged', received: body.length })
      client.print "HTTP/1.1 200 OK\r\n" \
                   "Content-Type: application/json\r\n" \
                   "Content-Length: #{resp_body.bytesize}\r\n" \
                   "Connection: close\r\n\r\n"
      client.print resp_body
    else
      resp_body = JSON.generate({ error: 'Route not found' })
      client.print "HTTP/1.1 404 Not Found\r\n" \
                   "Content-Type: application/json\r\n" \
                   "Content-Length: #{resp_body.bytesize}\r\n" \
                   "Connection: close\r\n\r\n"
      client.print resp_body
    end

    client.close
  end
end
