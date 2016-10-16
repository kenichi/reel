require 'reel'
require 'reel/h2/connection'
require 'reel/h2/stream'
require 'reel/h2/server'

module Reel

  module H2

    # http/2 psuedo-headers
    #
    AUTHORITY_KEY  = ':authority'
    METHOD_KEY     = ':method'
    PATH_KEY       = ':path'
    SCHEME_KEY     = ':scheme'
    STATUS_KEY     = ':status'

    module UpgradeConnection

      UPGRADE_RESPONSE =
        "HTTP/1.1 101 Switching Protocols\n" +
        "Connection: Upgrade\n" +
        "Upgrade: h2c\n\n"

      def request
        req = super

        # HTTP/2 upgrade request
        #
        if req.http2?
          socket = hijack_socket
          connection = H2::Connection.new socket, server
          socket.write UPGRADE_RESPONSE
          req.upgrade_to_h2 connection
          connection.read
          nil

        else
          req
        end
      end

    end
  end

  class Connection
    prepend H2::UpgradeConnection
  end

  class Request

    # Can the current request be upgraded to HTTP/2?
    def http2?; @request_info.http2_request?; end

    def upgrade_to_h2 connection
      connection.upgrade @request_info.http2_settings,
                         @request_info.http2_request_hash,
                         body.to_s
    end

    class Info

      H2C            = 'h2c'
      HTTP2_SETTINGS = 'HTTP2-Settings'
      HOST_KEY       = 'host'
      HTTP_SCHEME    = 'http'

      def http2_request?
        headers[UPGRADE] && headers[UPGRADE].downcase == H2C
      end

      def http2_settings
        headers[HTTP2_SETTINGS]
      end

      def http2_request_hash
        { H2::SCHEME_KEY    => HTTP_SCHEME,
          H2::METHOD_KEY    => http_method,
          H2::AUTHORITY_KEY => headers[HOST_KEY],
          H2::PATH_KEY      => url }
      end

    end
  end
end
