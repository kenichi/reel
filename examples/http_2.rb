#!/usr/bin/env ruby

require 'bundler/setup'
require 'reel/h2'
require 'pry'
require 'pry-byebug'

class Hello < Reel::H2::Stream

  def handle_stream
    case @request_headers[Reel::H2::PATH_KEY]
    when '/push_promise'

      promise_headers = {
        Reel::H2::METHOD_KEY    => 'GET',
        Reel::H2::AUTHORITY_KEY => @request_headers[Reel::H2::AUTHORITY_KEY],
        Reel::H2::PATH_KEY      => '/pushed.js',
        Reel::H2::SCHEME_KEY    => @request_headers[Reel::H2::SCHEME_KEY]
      }

      push_res = '(function(){ alert("hello h2 push promise!"); })();'
      push_stream = nil
      @stream.promise(promise_headers) do |push|
        push.headers({
          Reel::H2::STATUS_KEY => '200',
          'content-length' => push_res.bytesize.to_s,
          'content-type' => 'application/javascript'
        }, end_stream: false)
        push_stream = push
      end

      res = '<html>wait for it...<script src="/pushed.js"></script></html>'
      @stream.headers({
        Reel::H2::STATUS_KEY => '200',
        'content-length' => res.bytesize.to_s,
        'content-type' => 'text/html'
      }, end_stream: false)
      @stream.data res.slice!(0,3), end_stream: false
      @stream.data res
      @stream.close

      push_stream.data push_res.slice!(0,5), end_stream: false
      sleep 1
      push_stream.data push_res
      push_stream.close

    when '/favicon.ico'
      @stream.headers({
        Reel::H2::STATUS_KEY => '404',
        'content-length' => '0'
      }, end_stream: false)
      @stream.data ''
      @stream.close

    else
      res = "hello h2 world!\n"
      @stream.headers({
        Reel::H2::STATUS_KEY => '200',
        'content-length' => res.bytesize.to_s,
        'content-type' => 'text/plain'
      }, end_stream: false)
      @stream.data res.slice!(0,3), end_stream: false
      @stream.data res
      @stream.close
    end
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

h1_handler = ->(h1){ h1.each_request {|r| r.respond :ok, "hello, HTTP/1.x world!\n"}}

puts "*** Starting H2 TLS server on tcp://#{addr}:#{tls_port}"
tls_server = Reel::H2::Server::HTTPS.new(addr, tls_port, options, &h1_handler)

puts "*** Starting H2 Upgrade server on tcp://#{addr}:#{port}"
upgrade_server = Reel::H2::Server::HTTP.new(addr, port, options, &h1_handler)

sleep
