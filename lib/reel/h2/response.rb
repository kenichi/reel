module Reel
  module H2
    class Response

      def initialize status, body_or_headers = nil, body = ''
        self.status = status

        if Hash === body_or_headers
          @headers = body_or_headers.dup
          @body = body
        else
          @headers = {}
          @body = body_or_headers
        end

        case @body
        when String
          @headers[Reel::Response::CONTENT_LENGTH] ||= @body.bytesize.to_s
        when IO
          @headers[Reel::Response::CONTENT_LENGTH] ||= @body.stat.size.to_s
        when NilClass
          @headers[Reel::Response::CONTENT_LENGTH] = '0'
        else raise TypeError, "can't render #{@body.class} as a response body"
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
