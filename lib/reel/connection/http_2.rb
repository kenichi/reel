require 'http/2'

module Reel
  class Connection

    # HTTP/2 connection handler
    #
    class HTTP2
      include Celluloid::Logger

      BUFFER_SIZE = 16384
      UPGRADE_RESPONSE = ("HTTP/1.1 101 Switching Protocols\n" +
                          "Connection: Upgrade\n" +
                          "Upgrade: h2c\n\n").freeze

      attr_reader :buffer_size, :http2, :socket

      class << self

        # accessor for event generic http/2 callbacks
        #
        # @return [Hash] eventname => handler proc
        #
        def on(event = nil, &block)
          @on ||= {}
          return @on if event.nil?
          raise ArgumentError unless block_given?
          @on[event] = block
          @on
        end

      end

      # fire up a new HTTP2 connection on the socket
      #
      def initialize(socket, settings = {})

        # underlying Celluloid::IO::TCPSocket or OpenSSL::SSL::SSLSocket
        #
        @socket = socket

        # pull out upgrade extras
        #
        s = {
          body: settings.delete(:body),
          headers: settings.delete(:headers)
        }

        # fire up direct HTTP/2 connection
        #
        init_http2 settings

        # handle HTTP/1.1 Upgrade request with HTTP2-Settings header
        #
        unless settings.empty?

          debug "101 upgrading with HTTP2-Settings: #{settings.inspect}"
          @socket.write UPGRADE_RESPONSE

          s[:connection] = @http2

          # stream 1 is response to upgraded request
          # https://tools.ietf.org/html/rfc7540#section-3.2
          # TODO add upgrade handling to http-2
          #
          s[:stream] = @http2.new_stream
          s[:stream].instance_variable_set :@id, 1
          s[:stream].instance_variable_set :@state, :half_closed_remote

          # The first HTTP/2 frame sent by the server MUST be a server connection
          # preface (Section 3.5) consisting of a SETTINGS frame (Section 6.5).
          # https://tools.ietf.org/html/rfc7540#section-3.2
          #
          @http2.settings settings

          # TODO add upgrade handling to HTTP2::Server
          @http2.instance_variable_set :@state, :connected

          # the HTTP/1 style request is supposed to be used as the initial
          # state of stream:1... TODO still trying to figure this out
          #
          HTTP2.on[:stream][s]
        end

      end

      # init HTTP2::Server instance for handling the protocol
      #
      def init_http2(settings = {})
        @http2 = ::HTTP2::Server.new **settings

        # do the thing!
        @http2.on :frame do |bytes|
          @socket.write bytes
        end

        # handle streams... in a sort of 1.x-ish way TODO
        @http2.on :stream do |stream|

          req, buffer = {}, ''
          stream.on(:headers) {|h| req = Hash[*h.flatten]}
          stream.on(:data)    {|d| buffer << d}

          stream.on(:half_close) do
            HTTP2.on[:stream][{
              body: buffer,
              connection: @http2,
              headers: req,
              stream: stream
            }]
          end

        end
      end

      # shovel data from the socket into the parser.
      #
      def readpartial
        while !@socket.closed? && !@socket.eof?
          begin
            data = @socket.readpartial(BUFFER_SIZE)
            @http2 << data

          # hack around Reel::Connection#each_request being responsible for
          # shoveling into HTTP::Parser. +data+ gets fed to it on init during
          # rescue.
          #
          rescue ::HTTP2::Error::HandshakeError => he
            warn "degrading to HTTP/1"
            raise HTTP2ParseError.new data

          rescue => e
            error "Exception: #{e}, #{e.message} - closing socket."
            # STDERR.puts e.backtrace
            @socket.close
          end
        end
      end

    end
  end

end
