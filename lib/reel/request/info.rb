module Reel
  class Request
    class Info

      CASE_INSENSITVE_HASH = Hash.new do |hash, key|
        hash[hash.keys.find {|k| k =~ /#{key}/i}] if key
      end

      attr_reader :http_method, :url, :http_version, :headers

      def initialize(http_method, url, http_version, headers)
        @http_method  = http_method
        @url          = url
        @http_version = http_version
        @headers      = CASE_INSENSITVE_HASH.merge headers
      end

      UPGRADE   = 'Upgrade'.freeze
      WEBSOCKET = 'websocket'.freeze

      H2C            = 'h2c'.freeze
      HTTP2_SETTINGS = 'HTTP2-Settings'.freeze
      UINT16         = 'n'.freeze

      def websocket_request?
        headers[UPGRADE] && headers[UPGRADE].downcase == WEBSOCKET
      end

      def http2_request?
        headers[UPGRADE] && headers[UPGRADE].downcase == H2C
      end

      def http2_settings
        settings = []
        h2s = ::HTTP2::Buffer.new Base64.decode64 headers[HTTP2_SETTINGS]
        (h2s.length / 6).times do
          id = h2s.read(2).unpack(UINT16).first
          val = h2s.read_uint32
          name, _ = ::HTTP2::Framer::DEFINED_SETTINGS.find {|_name,v| v == id}
          settings << [name, val] if name
        end
        Hash[settings]
      end

    end
  end
end
