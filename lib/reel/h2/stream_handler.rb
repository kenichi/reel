module Reel
  module H2

    # base stream handling class for anonymous subclasses to descend from
    # see +StreamHandler.build+
    #
    class StreamHandler

      # creates an anonymous subclass of self, with +#handle_stream+ defined by
      # the given block
      #
      def self.build &block
        c = Class.new self
        c.instance_eval { define_method :handle_stream, &block }
        return c
      end

      # each stream event method is wrapped in a block to call a local instance
      # method of the same name
      #
      STREAM_EVENTS = [
        :active,
        :close,
        :half_close
      ]

      # the above take only the event, the following receive both the event
      # and the data
      #
      STREAM_DATA_EVENTS = [
        :headers,
        :data
      ]

      CONTENT_TYPE = 'content-type'

      attr_reader :connection,
                  :push_promises,
                  :request_headers,
                  :stream

      def initialize connection:, stream:
        self.stream = stream
        @connection = connection
        @request_headers = request_header_hash
        @push_promises = Set.new
        @body = ''
      end

      # set ivar, and bind +@stream+ events to +self+
      #
      def stream= stream
        @stream = stream
        STREAM_EVENTS.each {|e| @stream.on(e){ __send__ e}}
        STREAM_DATA_EVENTS.each {|e| @stream.on(e){|x| __send__ e, x}}
      end

      # called when client half-closes a stream
      #
      #   * override this in a subclass then pass that in HTTPS.new options
      #
      #     example:
      #
      #       class MyStreamHandler < Reel::H2::StreamHandler
      #         def handle_stream
      #           # do something
      #         end
      #       end
      #       Reel::H2::Server::HTTPS.new '127.0.0.1', 4567, sni: sni_options, stream_handler: MyStreamHandler
      #
      #   * pass a block to HTTPS.new which will be used to build an anonymous sublcass
      #     with the block defined as +#handle_stream+
      #
      #     example:
      #
      #       Reel::H2::Server::HTTPS.new '127.0.0.1', 4567, sni: sni_options do
      #         # do something
      #       end
      #
      # @see +HTTP2::Stream+
      #
      def handle_stream
        raise NotImplementedError
      end

      # --- request helpers

      # retreive the value of the +:path+ psuedo-header
      #
      def request_path
        @request_headers[PATH_KEY]
      end

      # retreive the value of the +:method+ psuedo-header
      #
      def request_method
        @request_headers[METHOD_KEY]
      end

      # ':authority' is the new 'host'
      #
      def request_authority
        @request_headers[AUTHORITY_KEY]
      end

      # attempt to get peeraddr[3] value from the socket
      #
      # @return [String, nil] the IP address of the connection
      #
      def request_addr
        addr = @connection.socket.peeraddr
        Array === addr ? addr[3] : nil
      end

      # ---

      # mimicing Reel::Connection#respond
      #
      # write status, headers, and data to +@stream+
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

        @response = case response
                    when Symbol, Fixnum, Integer
                      response = H2::Response.new(response, headers, body)
                    when H2::Response
                      response
                    else raise TypeError, "invalid response: #{response.inspect}"
                    end

        @response.respond_on(@stream)
        log :info, @response
      end

      # create a push promise, send the headers, then queue an asynchronous
      # task on the reactor to deliver the data
      #
      def push_promise *args
        pp = push_promise_for *args
        make_promise! pp
        @connection.server.async.handle_push_promise pp
        log :info, pp
      end

      # create a push promise
      #
      def push_promise_for path, body_or_headers = {}, body = nil
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

        PushPromise.new path, headers, body
      end

      # begin the new push promise stream from this +@stream+ by sending the
      # initial headers frame
      #
      # @see +PushPromise#make_on!+
      # @see +HTTP2::Stream#promise+
      #
      def make_promise! p
        p.make_on! @stream
        @push_promises << p
        p
      end

      # keep all promises made from this +@stream+
      #
      def keep_promises!
        @push_promises.each do |promise|
          @connection.server.async.handle_push_promise promise
          log :info, promise
        end
      end

      protected

      def active
        log :debug, 'client opened new stream'
      end

      # called by +@stream+ when this stream is closed, removes self from +@connection+
      #
      def close
        log :debug, "stream closed"
        @connection.remove_stream_handler self
      end

      # called by +@stream+ with a +Hash+ when request headers are complete
      #
      def headers h
        incoming_headers = Hash[*h.flatten]
        log :debug, "incoming headers: #{incoming_headers}"
        @request_headers.merge! incoming_headers
      end

      # called by +@stream+ with a +String+ body part
      #
      def data d
        log :debug, "payload chunk: <<#{d}>>"
        @body << d
      end

      # called by +@stream+ when body/request is complete, signaling that client
      # is ready for response(s)
      #
      def half_close
        log :debug, 'client closed its end of the stream'
        handle_stream
      end

      private

      # build a hash with case-insensitive key access
      #
      # NOTE: also translates '_' to '-' for symbol usage
      #
      def request_header_hash
        Hash.new do |hash, key|
          k = key.to_s.upcase
          k.gsub! '_', '-'
          _, value = hash.find {|header_key,v| header_key.upcase == k}
          hash[key] = value if value
        end
      end

      # convenience content-type header defaults for common types based on symbols
      #
      def default_headers sym
        ct = case sym
             when :css
               'text/css'
             when :html
               'text/html'
             when :js
               'application/javascript'
             when :json
               'application/json'
             when :png
               'image/png'
             when :text
               'text/plain'
             else raise ArgumentError.new "unknown default header type: #{sym}"
             end
        { CONTENT_TYPE => ct }
      end

      # --- logging helpers

      def log level, msg
        msg = case msg
              when Response;    format_response msg
              when PushPromise; format_push_promise msg
              when String;      "[stream #{@stream.id}] #{msg}"
              else;             msg
              end
        Logger.__send__ level, msg
      end

      def format_response response
        %{[stream #{@stream.id}] #{request_addr} } +
        %{"#{request_method} #{request_path} HTTP/2" } +
        %{#{response.status} #{response.content_length}}
      end

      def format_push_promise promise
        %{[stream #{promise.push_stream.id}] #{request_addr} } +
        %{"PUSH #{promise.path} HTTP/2" } +
        %{#{PushPromise::STATUS} #{promise.content_length}}
      end

    end
  end
end
