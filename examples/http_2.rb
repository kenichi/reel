#!/usr/bin/env ruby

require 'bundler/setup'
require 'reel/h2'
require 'pry'
require 'pry-byebug'

# Reel::Logger.level = :debug
# Reel::H2.verbose!

class Hello < Reel::H2::StreamHandler

  PUSH_PROMISE = '<html>wait for it...<img src="/logo.png"/><script src="/pushed.js"></script></html>'.freeze
  PUSHED_JS = '(function(){ alert("hello h2 push promise!"); })();'.freeze
  LOGO_PNG = File.read File.expand_path '../../logo.png', __FILE__

  def handle_stream
    case request_path
    when '/push_promise'
      push_promise '/logo.png', :png, LOGO_PNG

      pp = push_promise_for '/pushed.js', :js, PUSHED_JS
      pp.make_on! @stream
      respond :ok, :html, PUSH_PROMISE
      pp.keep!
      log :info, pp

    when '/pushed.js'
      respond :not_found
      # respond :ok, :js, PUSHED_JS

    when '/favicon.ico'
      respond :not_found

    when '/logo.png'
      respond :not_found
      # respond :ok, :png, LOGO_PNG

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
