module Reel
  module H2
    class Server < Reel::Server

      def handle_connection(socket)
        connection = H2::Connection.new(socket, self)
        connection.read
      rescue H2::ParseError => pe
        Logger.debug "Degrading to HTTP/1.x"
        super(socket, pe.data)
      end

      def read_from_connection connection
        connection.read
      end

      class HTTP < H2::Server
        include Reel::Server::Template::HTTP
      end

      class HTTPS < H2::Server
        ALPN_PROTOCOL = 'h2'

        def initialize(host, port, options={}, &callback)

          ssl_context      = OpenSSL::SSL::SSLContext.new

          # ssl_context.cert = OpenSSL::X509::Certificate.new options.fetch(:cert)
          # ssl_context.key  = OpenSSL::PKey::RSA.new options.fetch(:key)

          # ssl_context.ca_file          = options[:ca_file]
          # ssl_context.ca_path          = options[:ca_path]
          # ssl_context.extra_chain_cert = options[:extra_chain_cert]
          # ssl_context.verify_mode      = options[:verify_mode] || OpenSSL::SSL::VERIFY_PEER

          ssl_context.servername_cb    = ->(a) {
            socket, sni = *a
            ctx = socket.context

            if Hash === options[:sni][sni]
              ctx = OpenSSL::SSL::SSLContext.new
              ctx.cert = OpenSSL::X509::Certificate.new options[:sni][sni][:cert]
              ctx.key  = OpenSSL::PKey::RSA.new options[:sni][sni][:key]
              ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
              ctx.alpn_protocols = [ALPN_PROTOCOL]
              ctx.alpn_select_cb = ->(ps){ ps.find {|p| p == ALPN_PROTOCOL}}
              ctx
            end

            ctx
          }

          @tcpserver = Celluloid::IO::TCPServer.new(host, port)

          server = Celluloid::IO::SSLServer.new(@tcpserver, ssl_context)
          options.merge!(host: host, port: port)

          super(server, options, &callback)
        end

        def run
          loop do
            begin
              socket = @server.accept
            rescue OpenSSL::SSL::SSLError, Errno::ECONNRESET, Errno::EPIPE,
                   Errno::ETIMEDOUT, Errno::EHOSTUNREACH => ex
              Logger.warn "Error accepting SSLSocket: #{ex.class}: #{ex.to_s}"
              retry
            end

            socket = Reel::Spy.new(socket, @spy) if @spy
            async.handle_connection socket
          end
        end
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
