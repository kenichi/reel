require 'spec_helper'
require 'reel/h2'

Reel::Logger.level = :fatal
# Reel::Logger.level = :debug
# Reel::H2.verbose!

def with_h2(handler = nil)
  H2::TestStreamHandler.handler = handler || ->{ H2::Client.get }
  server = Reel::H2::Server::HTTP.new host: example_addr,
                                      port: example_port,
                                      stream_handler: H2::TestStreamHandler
  sleep 0.05
  yield server
ensure
  server.terminate if server && server.alive?
  H2::TestStreamHandler.handler = nil
end

module H2

  class Client

    CONN_EVENTS = [
      :altsvc,
      :close,
      :frame,
      :frame_sent,
      :frame_received,
      :goaway,
      :promise
    ]

    PROMISE_EVENTS = [ :headers, :data ]
    REQUEST_METHODS = [ :get, :post, :put, :delete, :options, :head ]

    STREAM_EVENTS = [
      :close,
      :half_close,
      :headers,
      :data,
      :altsvc
    ]

    attr_reader :streams

    def initialize addr: example_addr, port: example_port
      @addr = addr
      @port = port
      @streams = {}
      @socket = TCPSocket.new @addr, @port
      @client = HTTP2::Client.new
      yield self if block_given?
      bind_events
    end

    REQUEST_METHODS.each do |m|
      define_method m do |path: '/', headers: {}, body: nil|
        request method: m, path: path, headers: headers, body: body
      end
    end

    def on event, &block
      @on ||= {}
      return @on[event] if Proc === @on[event] unless block_given?
      return @on[event] = block if block_given?
      nil
    end

    class << self
      REQUEST_METHODS.each do |m|
        define_method m do |path: '/', headers: {}, body: nil|
          c = new
          c.__send__ m, path: path, headers: headers, body: body
          c
        end
      end
    end

    private

      def bind_events
        CONN_EVENTS.each do |e|
          if handler = on(e)
            @client.on e, &handler
          else
            default = "default_on_#{e}".to_sym
            if private_methods.include? default
              @client.on e, &method(default)
            end
          end
        end
      end

      def request method:, path:, headers: {}, body: nil
        s = @client.new_stream
        add_stream method: method, path: path, stream: s

        h = {
          Reel::H2::AUTHORITY_KEY => [@addr, @port.to_s].join(':'),
          Reel::H2::METHOD_KEY    => method.to_s.upcase,
          Reel::H2::PATH_KEY      => path,
          Reel::H2::SCHEME_KEY    => 'http'
        }.merge headers

        s.headers h, end_stream: body.nil?
        s.data body if body
        read
      end

      def add_stream method:, path:, stream:
        @streams[method] ||= {}
        @streams[method][path] ||= []
        @streams[method][path] << StreamInfo.new(client: self,
                                                 method: method,
                                                 path: path,
                                                 stream: stream)
      end

      def read
        while !@socket.closed? && !(@socket.eof? rescue true)
          data = @socket.readpartial(1024)
          # puts "received bytes: #{data.unpack("H*").first}"
          begin
            @client << data
          rescue => e
            puts "#{e.class} exception: #{e.message} - closing socket."
            e.backtrace.each { |l| puts "\t" + l }
            @socket.close
          end
        end
      end

      # ---

      def default_on_close
        @socket.close
      end

      def default_on_frame bytes
        # puts "writing bytes: #{bytes.unpack("H*").first}"
        @socket.sendmsg bytes
      end

      def default_on_goaway *args
        # puts "goaway: #{args.inspect}"
        @socket.close
      end

      def default_on_promise promise
        promise.on(:headers) do |h|
          puts "promise headers: #{h}"
        end

        promise.on(:data) do |d|
          puts "promise data: #{d}"
        end
      end

  end

  class StreamInfo

    attr_reader :headers, :body

    def initialize client:, method:, path:, stream:
      @client = client
      @method = method
      @path   = path
      @stream = stream
      @closed = false
      @body   = ''

      bind_events
    end

    def closed?
      @closed
    end

    def bind_events
      @stream.on(:close) do
        @closed = true
      end

      @stream.on(:half_close) do
        # puts 'closing client-end of the stream'
      end

      @stream.on(:headers) do |h|
        # puts "response headers: #{h}"
        @headers = Hash[h]
      end

      @stream.on(:data) do |d|
        # puts "response data chunk: <<#{d}>>"
        @body << d
      end

      @stream.on(:altsvc) do |f|
        # puts "received ALTSVC #{f}"
      end
    end

    def to_h
      { headers: headers, body: body }
    end

    def inspect
      "#{super} #{to_h.inspect}"
    end

  end

  class TestStreamHandler < Reel::H2::StreamHandler
    RSpec::Expectations::Syntax.enable_expect self
    include RSpec::Matchers

    class << self
      attr_accessor :handler
    end

    attr_reader :expect_error

    def handle_stream
      instance_eval &TestStreamHandler.handler
    end

  end

end
