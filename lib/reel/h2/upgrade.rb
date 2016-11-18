require 'reel/h2'

# HTTP/1.x Connection: upgrade -> HTTP/2 functionality
#
# * additions to various H2 classes
# * prepending for Reel::Connection
#
module Reel
  module H2

    class Server
      class HTTPS

        # create an upgrade-only, non-TLS server from an existing H2 TLS server
        #
        def upgrade_server host:, port:, **options
          Reel::Server::HTTP.new host, port, **options do |connection|

            # assign self as server for the connection, allowing connection
            # additions below access
            #
            # @see +Upgrade::Connection#request+
            #
            connection.server = self

            # only handle single, upgrade requests
            #
            connection.request
          end
        end

      end
    end

    class Connection

      # forward Connection#upgrade to the +HTTP2::Server+ parser
      #
      def upgrade settings, headers, body
        @parser.upgrade settings, headers, body
      end

    end

    class StreamHandler
      module Upgrade

        OPTIONS = 'OPTIONS'

        # default handler for OPTIONS upgrade, 200s with no body
        #
        def handle_upgrade_options
          respond :ok
        end

        protected

        # wrap original +#half_close+ in check for upgrade
        #
        def half_close
          if @request_headers[:upgrade]
            h2c_upgrade
          else
            super
          end
        end

        # check upgrade method and call appropriate handler method
        #
        def h2c_upgrade
          log :debug, "Processing h2c Upgrade request"
          if @request_headers[METHOD_KEY] == OPTIONS
            handle_upgrade_options
          else
            handle_stream
          end
        end

      end

      prepend Upgrade
    end

    # additions to non-H2 Reel classes
    #
    module Upgrade

      module Server

        # allow connections to be read from asynchronously by the reactor, after
        # hijack from request loop
        #
        def read_from_connection connection
          connection.read
        end

      end

      Reel::Server.include Server

      module Connection

        # see https://tools.ietf.org/html/rfc7540#section-3.2
        #
        UPGRADE_RESPONSE =
          "HTTP/1.1 101 Switching Protocols\n" +
          "Connection: Upgrade\n" +
          "Upgrade: h2c\n\n"

        # wrap existing request with a check for h2 upgrade, similar to check
        # for websocket ugprade
        #
        # NOTE: socket read task is "hijacked" from one reactor to another
        #
        def request
          req = super

          # HTTP/2 upgrade request
          #
          if req && req.h2?
            Logger.debug "Upgrading to HTTP/2"
            socket = hijack_socket
            connection = H2::Connection.new socket: socket, server: server
            socket.write UPGRADE_RESPONSE
            req.upgrade_to_h2 connection
            server.async.read_from_connection connection
            nil

          else
            req
          end
        end

      end

      Reel::Connection.prepend Connection

      module Request

        # can the current request be upgraded to HTTP/2?
        #
        def h2?; @request_info.h2_request?; end

        # gather the info needed and do the upgrade
        #
        def upgrade_to_h2 connection
          connection.upgrade @request_info.h2_settings,
                             @request_info.h2_request_hash,
                             body.to_s
        end

        # see https://tools.ietf.org/html/rfc7540#section-3.2
        #
        module Info
          H2C            = 'h2c'
          HTTP2_SETTINGS = 'HTTP2-Settings'
          HOST_KEY       = 'host'
          HTTP_SCHEME    = 'http'
          UPGRADE        = 'upgrade'

          # does this request contain the 'upgrade' header and is the value 'h2c'?
          #
          # TODO: check for 'connection: Upgrade, HTTP2-Settings' header?
          #
          def h2_request?
            headers[UPGRADE] && headers[UPGRADE].downcase == H2C
          end

          # retrieve the value of the 'HTTP2-Settings' header
          #
          def h2_settings
            headers[HTTP2_SETTINGS]
          end

          # translate request header hash to HTTP/2
          #
          def h2_request_hash
            headers.dup.update H2::SCHEME_KEY    => HTTP_SCHEME,
                               H2::METHOD_KEY    => http_method,
                               H2::AUTHORITY_KEY => headers[HOST_KEY],
                               H2::PATH_KEY      => url,
                               UPGRADE           => H2C
          end
        end

        Reel::Request::Info.include Info

      end

      Reel::Request.include Request

    end
  end

end
