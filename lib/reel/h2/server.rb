module Reel
  module H2

    # base H2 server, a direct subclass of +Reel::Server+
    #
    class Server < Reel::Server

      def initialize server, **options, &on_stream
        @on_stream = on_stream
        super server, options
      end

      # set/return the +@stream_handler+ for this server, from either the
      # +:stream_handler+ option or the +@on_stream+ block
      #
      def stream_handler
        @stream_handler ||= options[:stream_handler] or StreamHandler.build &@on_stream
      end

      # build a new connection object, and start reading from the socket
      #
      def handle_connection socket
        H2::Connection.new(socket: socket, server: self).read
      end

      # allow for push promises to be kept asynchronously by the reactor
      #
      def handle_push_promise push_promise
        push_promise.keep!
      end

      # 'h2c' server - for plaintext HTTP/2 connection
      #
      # NOTE: browsers don't support this and probably never will
      #
      # @see https://tools.ietf.org/html/rfc7540#section-3.4
      # @see https://hpbn.co/http2/#upgrading-to-http2
      #
      class HTTP < H2::Server

        # create a new h2c server
        #
        def initialize host:, port:, **options, &callback
          @tcpserver = Celluloid::IO::TCPServer.new host, port
          options.merge! host: host, port: port
          super @tcpserver, options, &callback
        end

      end

    end

  end
end

require 'reel/h2/server/https'
