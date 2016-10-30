#!/usr/bin/env ruby

require 'bundler/setup'
require 'reel/h2'
require 'pry'
require 'pry-byebug'

Reel::Logger.level = :debug

class Hello < Reel::H2::StreamHandler

  PUSH_PROMISE = '<html>wait for it...<script src="/pushed.js"></script></html>'.freeze
  PUSHED_JS = '(function(){ alert("hello h2 push promise!"); })();'.freeze

  def handle_stream
    case path
    when '/push_promise'
      push_promise '/pushed.js', :js, PUSHED_JS
      respond :ok, :html, PUSH_PROMISE
      keep_promises!

    when '/pushed.js'
      respond :not_found
      # respond :ok, :js, PUSHED_JS

    when '/favicon.ico'
      respond :not_found

    else
      respond :ok, :text, "hello h2 world!\n"
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
