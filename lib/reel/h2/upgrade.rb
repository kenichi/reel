module Reel
  module H2
    module Upgrade

      module Connection

        UPGRADE_RESPONSE =
          "HTTP/1.1 101 Switching Protocols\n" +
          "Connection: Upgrade\n" +
          "Upgrade: h2c\n\n"

        def request
          req = super

          # HTTP/2 upgrade request
          #
          if req.h2?
            socket = hijack_socket
            connection = H2::Connection.new socket, server
            socket.write UPGRADE_RESPONSE
            req.upgrade_to_h2 connection
            server.async.read_from_connection connection
            nil

          else
            req
          end
        end

      end

      Reel::Connection.prepend H2::Upgrade::Connection

      module Request
        # Can the current request be upgraded to HTTP/2?
        def h2?; @request_info.h2_request?; end

        def upgrade_to_h2 connection
          connection.upgrade @request_info.h2_settings,
                             @request_info.h2_request_hash,
                             body.to_s
        end

        module Info
          H2C            = 'h2c'
          HTTP2_SETTINGS = 'HTTP2-Settings'
          HOST_KEY       = 'host'
          HTTP_SCHEME    = 'http'

          def h2_request?
            headers[Reel::Request::Info::UPGRADE] && headers[Reel::Request::Info::UPGRADE].downcase == H2C
          end

          def h2_settings
            headers[HTTP2_SETTINGS]
          end

          def h2_request_hash
            { H2::SCHEME_KEY    => HTTP_SCHEME,
              H2::METHOD_KEY    => http_method,
              H2::AUTHORITY_KEY => headers[HOST_KEY],
              H2::PATH_KEY      => url }
          end
        end

        Reel::Request::Info.include H2::Upgrade::Request::Info

      end

      Reel::Request.include H2::Upgrade::Request

    end
  end

end


