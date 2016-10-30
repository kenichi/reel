module Reel
  module H2
    class Stream

      STREAM_EVENTS = [
        :active,
        :close,
        :half_close
      ]

      STREAM_DATA_EVENTS = [
        :headers,
        :data
      ]

      OPTIONS = 'OPTIONS'

      def initialize stream, connection
        @stream = stream
        @connection = connection
        @request_headers = request_header_hash
        @buffer = ''
        init_stream
      end

      def log level, msg
        Logger.__send__ level, "[stream #{@stream.id}] #{msg}"
      end

      def init_stream
        STREAM_EVENTS.each {|e| @stream.on(e){ __send__ e}}
        STREAM_DATA_EVENTS.each {|e| @stream.on(e){|x| __send__ e, x}}
      end

      protected

      def active
        log :debug, 'client opened new stream'
      end

      def close
        log :debug, "stream closed"
        @connection.remove_stream_handler self
      end

      def headers h
        incoming_headers = Hash[*h.flatten]
        log :debug, "incoming headers: #{incoming_headers}"
        @request_headers.merge! incoming_headers
      end

      def data d
        log :debug, "payload chunk: <<#{d}>>"
        @buffer << d
      end

      def half_close
        log :debug, 'client closed its end of the stream'
        if @request_headers[:upgrade]
          h2c_upgrade
        else
          log :debug, 'handling half close non-upgrade'
          handle_stream
        end
      end

      def h2c_upgrade
        log :debug, "Processing h2c Upgrade request"
        if @request_headers[METHOD_KEY] == OPTIONS
          handle_upgrade_options
        else
          handle_stream
        end
      end

      # ---

      def handle_stream
        raise NotImplementedError
      end

      def handle_upgrade_options
        @stream.headers({
          Reel::H2::STATUS_KEY => '200',
          'content-length' => '0'
        })
        @stream.close
      end

      # ---

      private

      def request_header_hash
        Hash.new do |hash, key|
          k = key.to_s.upcase
          k.gsub! '_', '-'
          _, value = hash.find {|header_key,v| header_key.upcase == k}
          hash[key] = value if value
        end
      end

    end
  end
end
