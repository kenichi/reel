#!/usr/bin/env ruby
# frozen_string_literals: true

require 'bundler/setup'
require 'date'
require 'pry'
require 'pry-byebug'
require 'reel/h2/upgrade'
require 'terraformer' # might need to add this to Gemfile

Reel::Logger.level = :debug
Reel::H2.verbose!

PUSH_PROMISE = '<html>wait for it...<img src="/logo.png"/><script src="/pushed.js"></script><script src="/sse.js"></script></html>'
PUSHED_JS    = '(()=>{ alert("hello h2 push promise!"); })();'
LOGO_PNG     = File.read File.expand_path '../../logo.png', __FILE__
SSE_JS       =<<~EOJS
  var es = new EventSource('/events.json');
  es.addEventListener('example', e => {
    var data = JSON.parse(e.data);
    console.log(data);
  });
EOJS

class EventGenerator
  include Celluloid

  def initialize
    @listeners = Set.new
    @event_count = {}
    @point = Terraformer::Point.new -121.6970, 45.3781 # mt. hood
  end

  def add_stream_handler sh
    @listeners << sh
    @event_count[sh] = 0
  end

  def remove_stream_handler sh
    @listeners.delete sh
    @event_count.delete sh
  end

  def generate
    sleep rand(5) + 1
    data = {
      geojson: @point.random_points(1).first.to_feature.to_hash,
      date: DateTime.now.iso8601
    }.to_json
    data =<<~EODATA
      event: example
      data: #{data}

    EODATA

    @listeners.each do |sh|
      @event_count[sh] += 1
      if @event_count[sh] > 5
        stream_data data: data, to: sh
        remove_stream_handler sh
      else
        stream_data data: data, to: sh, end_stream: false
      end
    end

    # puts "EVENT:\n#{data}\n\n"

    async.generate
  end

  def stream_data data:, to:, end_stream: true
    begin
      to.stream.data data, end_stream: end_stream
    rescue HTTP2::Error::StreamClosed => sc
      Reel::Logger.warn "stream closed: #{sc.message}"
      remove_stream_handler to
    rescue => e
      Reel::Logger.warn "execption: #{e.message}"
      remove_stream_handler to
    end
  end

end

event = EventGenerator.new
event.async.generate

options  = {
  host: '127.0.0.1',
  port: 4430,
  sni: {
    'example.com' => {
      cert: File.read('cert.pem'),
      key: File.read('key.pem'),
    }
  }
}

puts "*** Starting H2 TLS server on tcp://#{options[:host]}:#{options[:port]}"
h2_tls_server = Reel::H2::Server::HTTPS.new **options do

  # this block is actually overriding `#handle_stream` in an anonymous
  # `StreamHandler` descendent class. see `StreamBuilder.build`

  case request_path
  when '/push_promise'
    push_promise '/logo.png', :png, LOGO_PNG
    push_promise '/sse.js', :js, SSE_JS

    pp = push_promise_for '/pushed.js', :js, PUSHED_JS
    pp.make_on! stream
    respond :ok, :html, PUSH_PROMISE
    pp.keep!
    log :info, pp

  when '/pushed.js'
    respond :not_found

  when '/favicon.ico'
    respond :not_found

  when '/logo.png'
    respond :not_found

  when '/sse.js'
    respond :ok, :js, SSE_JS

  when '/events.json'
    stream.headers Reel::H2::STATUS_KEY => '200',
                    'content-type' => 'text/event-stream'
    event.add_stream_handler self

  else
    respond :ok, :text, "hello h2 world!\n"
    goaway
  end

end

upgrade_options = options.dup
upgrade_options[:port] = 9292
puts "*** Starting H2 Upgrade server on tcp://#{upgrade_options[:host]}:#{upgrade_options[:port]}"
upgrade_server = h2_tls_server.upgrade_server **upgrade_options

h2_options = options.dup
h2_options[:port] = 8080
h2_options[:stream_handler] = h2_tls_server.stream_handler
puts "*** Starting H2 server on tcp://#{h2_options[:host]}:#{h2_options[:port]}"
h2_server = Reel::H2::Server::HTTP.new **h2_options

sleep
