module Reel
  module H2

    # mimic +Reel::Response+ behavior by providing similar API to respond to a
    # +HTTP2::Stream+
    #
    class Response

      CONTENT_LENGTH = 'content-length'.freeze

      attr_reader :content_length, :status

      # build a new +Response+ object
      #
      # @param [Integer, Symbol] status HTTP status code or symbol from
      #                          +Reel::Reponse::SYMBOL_TO_STATUS_CODE+
      # @param [Hash, String] body_or_headers
      # @param [String] body optional
      #
      # TODO: should mimic existing API like this?
      #
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

      # sets the content length in the headers by the byte size of +@body+
      #
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

      # sets +@status+ either from given integer value (HTTP status code) or by
      # mapping a +Symbol+ in +Reel::Response::SYMBOL_TO_STATUS_CODE+ to one
      #
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

      # send the headers and body out on +stream+
      #
      # NOTE: +:status+ must come first?
      #
      def respond_on stream
        headers = { Reel::H2::STATUS_KEY => @status.to_s }.merge @headers
        stream.headers headers
        stream.data @body
      end

    end
  end
end
