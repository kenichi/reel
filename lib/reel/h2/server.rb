module Reel
  module H2

    class Server < Reel::Server

      def handle_connection socket
        connection = H2::Connection.new socket, self
        connection.read
      rescue H2::ParseError => pe
        Logger.debug "Degrading to HTTP/1.x"
        super socket, pe.data
      end

      def read_from_connection connection
        connection.read
      end

      class HTTP < H2::Server
        include Reel::Server::Template::HTTP
      end

      class HTTPS < H2::Server

        ALPN_PROTOCOL        = 'h2'
        ALPN_SELECT_CALLBACK = ->(ps){ ps.find {|p| p == ALPN_PROTOCOL }}
        EC_KEY               = 'prime256v1'
        TMP_ECDH_CALLBACK    = ->(*_){ OpenSSL::PKey::EC.new EC_KEY }

        def initialize host, port, options = {}, &callback
          init_sni options.delete(:sni)
          options.merge! host: host, port: port
          @tcpserver = Celluloid::IO::TCPServer.new host, port
          @sslserver = Celluloid::IO::SSLServer.new @tcpserver, create_ssl_context
          super @sslserver, options, &callback
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

        private

        def init_sni sni = {}
          @sni          = sni
          @sni_callback = @sni[:callback] || method(:sni_callback)
        end

        def sni_callback args
          socket, name = *args
          if sni_opts = @sni[name] and Hash === sni_opts
            create_ssl_context cert: sni_opts[:cert], key: sni_opts[:key]
          else
            socket.context
          end
        end

        def create_ssl_context **opts
          ctx                   = OpenSSL::SSL::SSLContext.new
          ctx.alpn_protocols    = [ALPN_PROTOCOL]
          ctx.alpn_select_cb    = ALPN_SELECT_CALLBACK
          ctx.ca_file           = opts[:ca_file] if opts[:ca_file]
          ctx.ca_path           = opts[:ca_path] if opts[:ca_path]
          ctx.cert              = OpenSSL::X509::Certificate.new opts[:cert] if opts[:cert]
          ctx.ciphers           = opts[:ciphers] || OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:ciphers]
          ctx.extra_chain_cert  = opts[:extra_chain_cert] if opts[:extra_chain_cert]
          ctx.key               = OpenSSL::PKey::RSA.new opts[:key] if opts[:key]
          ctx.options           = opts[:options] || OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
          ctx.servername_cb     = @sni_callback
          ctx.ssl_version       = :TLSv1_2
          ctx.tmp_ecdh_callback = TMP_ECDH_CALLBACK
          ctx
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
