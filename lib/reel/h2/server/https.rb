module Reel
  module H2
    class Server

      # 'h2' server - for TLS 1.2 ALPN HTTP/2 connection
      #
      # @see https://tools.ietf.org/html/rfc7540#section-3.3
      #
      class HTTPS < H2::Server

        ALPN_PROTOCOL        = 'h2'
        ALPN_SELECT_CALLBACK = ->(ps){ ps.find {|p| p == ALPN_PROTOCOL }}
        EC_KEY               = 'prime256v1'
        TMP_ECDH_CALLBACK    = ->(*_){ OpenSSL::PKey::EC.new EC_KEY }

        # create a new h2 server that uses SNI to determine TLS cert/key to use
        #
        # @see https://en.wikipedia.org/wiki/Server_Name_Indication
        #
        # @param [String] host the IP address for this server to listen on
        # @param [Integer] port the TCP port for this server to listen on
        # @param [Hash] options
        #
        # == SNI options with default callback
        #
        # [:sni] Hash with domain name +String+ keys and +Hash+ values:
        #     [:cert] +String+ TLS certificate
        #     [:key] +String+ TLS key
        #
        # == SNI options with _custom_ callback
        #
        # [:sni] Hash:
        #     [:callback] +Proc+ creates +OpenSSL::SSL::SSLContext+ for each
        #                        connection
        #
        def initialize host:, port:, **options, &on_stream
          @sni          = options.delete(:sni) || {}
          @sni_callback = @sni[:callback] || method(:sni_callback)
          @tcpserver    = Celluloid::IO::TCPServer.new host, port
          @sslserver    = Celluloid::IO::SSLServer.new @tcpserver, create_ssl_context
          options.merge! host: host, port: port
          super @sslserver, options
        end

        # accept a socket connection, possibly attach spy, hand off to +#handle_connection+
        # asyncronously, repeat
        #
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

        # default SNI callback - builds SSLContext from cert/key by domain name in +@sni+
        # or returns existing one if name is not found
        #
        def sni_callback args
          socket, name = *args
          if sni_opts = @sni[name] and Hash === sni_opts
            create_ssl_context cert: sni_opts[:cert], key: sni_opts[:key]
          else
            socket.context
          end
        end

        # builds a new SSLContext suitable for use in 'h2' connections
        #
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
  end
end
