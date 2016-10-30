module Reel
  module H2
    class StreamHandler

      STREAM_EVENTS = [
        :active,
        :close,
        :half_close
      ]

      STREAM_DATA_EVENTS = [
        :headers,
        :data
      ]

      CONTENT_TYPE = 'content-type'
      OPTIONS      = 'OPTIONS'

      def initialize stream, connection
        self.stream = stream
        @connection = connection
        @request_headers = request_header_hash
        @push_promises = Set.new
        @body = ''
      end

      def log level, msg
        Logger.__send__ level, "[stream #{@stream.id}] #{msg}"
      end

      def stream= stream
        @stream = stream
        STREAM_EVENTS.each {|e| @stream.on(e){ __send__ e}}
        STREAM_DATA_EVENTS.each {|e| @stream.on(e){|x| __send__ e, x}}
      end

      def path
        @request_headers[Reel::H2::PATH_KEY]
      end

      # ---

      def handle_stream
        raise NotImplementedError
      end

      def handle_upgrade_options
        respond :ok
      end

      # ---

      # mimicing Reel::Connection#respond
      #
      def respond response, body_or_headers = {}, body = ''
        case body_or_headers
        when Hash
          headers = body_or_headers
        when Symbol
          headers = default_headers body_or_headers
        else
          headers = {}
          body = body_or_headers
        end

        case response
        when Symbol, Fixnum, Integer
          response = H2::Response.new(response, headers, body)
        when H2::Response
        else raise TypeError, "invalid response: #{response.inspect}"
        end

        response.respond_on(@stream)
      end

      def push_promise path, body_or_headers = {}, body = nil
        case body_or_headers
        when Hash
          headers = body_or_headers
        when Symbol
          headers = default_headers body_or_headers
        else
          headers = {}
          body = body_or_headers
        end

        headers.merge! Reel::H2::AUTHORITY_KEY => @request_headers[Reel::H2::AUTHORITY_KEY],
                       Reel::H2::SCHEME_KEY    => @request_headers[Reel::H2::SCHEME_KEY]

        pp = PushPromise.new path, headers, body
        pp.make_on! @stream
        @push_promises << pp
        pp
      end

      def keep_promises!
        @push_promises.each do |promise|
          @connection.server.async.handle_push_promise promise
        end
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
        @body << d
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

      private

      def request_header_hash
        Hash.new do |hash, key|
          k = key.to_s.upcase
          k.gsub! '_', '-'
          _, value = hash.find {|header_key,v| header_key.upcase == k}
          hash[key] = value if value
        end
      end

      def default_headers sym
        ct = case sym
             when :html
               'text/html'
             when :js
               'application/javascript'
             when :json
               'application/json'
             when :text
               'text/plain'
             else raise ArgumentError.new "unknown default header type: #{sym}"
             end
        { CONTENT_TYPE => ct }
      end

    end
  end
end
