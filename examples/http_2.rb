#!/usr/bin/env ruby

require 'bundler/setup'
require 'reel/h2'

addr, port = '127.0.0.1', 4567

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

puts "*** Starting H2 HTTP server on tcp://#{addr}:#{port}"
server = Reel::H2::Server::HTTP.run(addr, port, h2: Hello) do |h1|
  h1.each_request do |request|
    request.respond :ok, "hello, world!\n"
  end
end
