module Reel
  module H2
    class Server < Reel::Server

      def handle_connection(socket)
        connection = H2::Connection.new(socket, self, @options[:h2])
        connection.read
      rescue H2::ParseError => pe
        Logger.debug "Degrading to HTTP/1.x"
        super(socket, pe.data)
      end

      class HTTP < H2::Server
        include Reel::Server::Template::HTTP
      end

      class HTTPS < H2::Server
        include Reel::Server::Template::HTTPS
      end

    end

    # caused by ::HTTP2::Error::HandshakeError
    # contains the data read from socket, so the HTTP 1.x parser doesn't miss out.
    #
    class ParseError < StandardError
      attr_reader :data
      def initialize data
        @data = data
        super()
      end
    end
  end
end
