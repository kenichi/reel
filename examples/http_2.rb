#!/usr/bin/env ruby

require 'bundler/setup'
require 'reel/h2'
require 'pry'

class Hello < Reel::H2::Stream

  def handle_stream
    res = "hello world!\n"
    @stream.headers({
      Reel::H2::STATUS_KEY => '200',
      'content-length' => res.bytesize.to_s,
      'content-type' => 'text/plain'
    }, end_stream: false)
    @stream.data res.slice!(0,3), end_stream: false
    @stream.data res
  end

end

addr, port = '127.0.0.1', 4430
options = {
  # spy: true,
  h2: Hello,
  sni: {
    'example.com' => {
      cert: File.read('cert.pem'),
      key: File.read('key.pem'),
    }
  }
}

puts "*** Starting H2 TLS server on tcp://#{addr}:#{port}"
server = Reel::H2::Server::HTTPS.run(addr, port, options) do |h1|
  h1.each_request do |request|
    request.respond :ok, "hello, world!\n"
  end
end
