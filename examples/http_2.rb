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

addr, port, tls_port = '127.0.0.1', 9292, 4430
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

h1_handler = ->(h1){ h1.each_request {|r| r.respond :ok, "hello, world!\n"}}

puts "*** Starting H2 TLS server on tcp://#{addr}:#{tls_port}"
tls_server = Reel::H2::Server::HTTPS.new(addr, tls_port, options, &h1_handler)
puts "*** Starting H2 Upgrade server on tcp://#{addr}:#{port}"
upgrade_server = Reel::H2::Server::HTTP.run(addr, port, options, &h1_handler)
