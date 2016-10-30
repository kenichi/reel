module Reel
  module H2
    class Response

      CONTENT_LENGTH = 'content-length'.freeze

      attr_reader :content_length, :status

      def initialize status, body_or_headers = nil, body = ''
        self.status = status

        if Hash === body_or_headers
          @headers = body_or_headers.dup
          @body = body
        else
          @headers = {}
          @body = body_or_headers
        end

        init_content_length
      end

      def init_content_length
        @content_length = case @body
          when String
            @body.bytesize.to_s
          when IO
            @body.stat.size.to_s
          when NilClass
            '0'
          else
            raise TypeError, "can't render #{@body.class} as a response body"
          end

        unless @headers.any? {|k,_| k.downcase == CONTENT_LENGTH}
          @headers[CONTENT_LENGTH] = @content_length
        end
      end

      def status= status
        case status
        when Integer
          @status = status
        when Symbol
          if code = Reel::Response::SYMBOL_TO_STATUS_CODE[status]
            self.status = code
          else
            raise ArgumentError, "unrecognized status symbol: #{status}"
          end
        else
          raise TypeError, "invalid status type: #{status.inspect}"
        end
      end

      def respond_on stream
        headers = { Reel::H2::STATUS_KEY => @status.to_s }.merge @headers
        stream.headers headers
        stream.data @body
      end

    end
  end
end
