require 'http/2'

module Reel
  module H2

    # handles reading data from the +@socket+ into the +HTTP2::Server+ +@parser+,
    # callbacks from the +@parser+, and closing of the +@socket+
    #
    class Connection
      extend Forwardable

      # each +@parser+ event method is wrapped in a block to call a local instance
      # method of the same name
      #
      PARSER_EVENTS = [
        :frame,
        :frame_sent,
        :frame_received,
        :stream
      ]

      # delegated to the +@parser+ to handle server "commands"
      #
      PARSER_COMMANDS = [
        :new_stream,
        :goaway
      ]

      def_delegators :@parser, *PARSER_COMMANDS

      attr_reader :server, :socket

      def initialize socket:, server:
        @socket = socket
        @server = server
        @parser = ::HTTP2::Server.new
        @stream_handlers = Set.new

        # bind parser events to this instance
        #
        PARSER_EVENTS.each {|e| @parser.on(e){|x| __send__ e, x}}

        Logger.debug "new H2::Connection: #{self}" if H2.verbose?
      end

      # remove a +StreamHandler+ instance from our local set
      #
      # see #stream
      #
      def remove_stream_handler sh
        @stream_handlers.delete sh
      end

      # begins the read loop, handling all errors with a log message,
      # backtrace, and closing the +@socket+
      #
      def read
        begin
          while !@socket.closed? && !(@socket.eof? rescue true)
            data = @socket.readpartial(1024)
            # Logger.debug "Received bytes: #{data.unpack("H*").first}"
            @parser << data
          end
          close

        rescue => e
          Logger.error "Exception: #{e.message} - closing socket"
          STDERR.puts e.backtrace
          close

        end
      end

      def close
        @socket.close if @socket
      end

      protected

      # +@parser+ event methods

      # called by +@parser+ with a binary frame to write to the +@socket+
      #
      def frame b
        Logger.debug "Writing bytes: #{truncate_string(b.unpack("H*").first)}" if Reel::H2.verbose?
        @socket.write b
      end

      def frame_sent f
        Logger.debug "Sent frame: #{truncate_frame(f).inspect}" if Reel::H2.verbose?
      end

      def frame_received f
        Logger.debug "Received frame: #{truncate_frame(f).inspect}" if Reel::H2.verbose?
      end

      # the +@parser+ calls this when a new stream has been initiated by the
      # client, constructs new +StreamHandler+ descendent
      #
      def stream s
        @stream_handlers << server.stream_handler.new(connection: self, stream: s)
      end

      private

      def truncate_string s
        (String === s && s.length > 64) ? "#{s[0,64]}..." : s
      end

      def truncate_frame f
        f.reduce({}) { |h, (k, v)| h[k] = truncate_string(v); h }
      end

    end
  end
end
