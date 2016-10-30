require 'http/2'

module Reel
  module H2
    class Connection
      extend Forwardable

      PARSER_EVENTS = [
        :frame,
        :frame_sent,
        :frame_received,
        :stream
      ]

      PARSER_COMMANDS = [
        :new_stream,
        :goaway
      ]

      def_delegators :@parser, *PARSER_COMMANDS

      attr_reader :server

      def initialize socket, server
        @socket = socket
        @server = server

        @parser = ::HTTP2::Server.new

        @stream_handler = @server.options[:h2] || StreamHandler
        @stream_handlers = Set.new

        PARSER_EVENTS.each {|e| @parser.on(e){|x| __send__ e, x}}
      end

      def remove_stream_handler sh
        @stream_handlers.delete sh
      end

      def read
        begin
          while !@socket.closed? && !(@socket.eof? rescue true)
            data = @socket.readpartial(1024)
            # Logger.debug "Received bytes: #{data.unpack("H*").first}"
            @parser << data
          end
          close

        rescue ::HTTP2::Error::HandshakeError => he
          raise H2::ParseError.new data

        rescue => e
          Logger.error "Exception: #{e.message} - closing socket"
          STDERR.puts e.backtrace
          close

        end
      end

      def upgrade settings, request_hash, body
        @parser.upgrade settings, request_hash, body
      end

      def close
        @socket.close if @socket
      end

      protected

      def frame b
        # Logger.debug "Writing bytes: #{b.unpack("H*").first}"
        @socket.write b
      end

      def frame_sent f
        Logger.debug "Sent frame: #{f.inspect}"
      end

      def frame_received f
        Logger.debug "Received frame: #{f.inspect}"
      end

      def stream s
        @stream_handlers << @stream_handler.new(s, self)
      end

    end
  end
end
