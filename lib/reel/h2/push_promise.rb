module Reel
  module H2
    class PushPromise

      GET = 'GET'

      def initialize path, body_or_headers = {}, body = nil
        if Hash === body_or_headers
          headers = body_or_headers.dup
          @body = body
        else
          headers = {}
          @body = body_or_headers
        end

        @promise_headers = {
          Reel::H2::METHOD_KEY    => GET,
          Reel::H2::AUTHORITY_KEY => headers.delete(Reel::H2::AUTHORITY_KEY),
          Reel::H2::PATH_KEY      => path,
          Reel::H2::SCHEME_KEY    => headers.delete(Reel::H2::SCHEME_KEY)
        }

        @push_headers = {
          Reel::H2::STATUS_KEY           => '200',
          Reel::Response::CONTENT_LENGTH => @body.bytesize.to_s
        }.merge headers

        @fsm = FSM.new
      end

      def make_on! stream
        @fsm.transition :made
        stream.promise(@promise_headers) do |push|
          push.headers @push_headers
          @push_stream = push
        end
        self
      end

      def keep! x = nil
        @fsm.transition :kept
        if x.nil?
          @push_stream.data @body
        else
          body = @body.dup
          loop do
            @push_stream.data body.slice!(0, x), end_stream: false
            yield if block_given?
            break if body.bytesize <= x
          end if body.bytesize > x
          @push_stream.data body
        end
      end

      def cancel!
        @fsm.transition :canceled
      end

      class FSM
        include Celluloid::FSM
        default_state :init
        state :init, to: [:canceled, :made]
        state :made, to: [:canceled, :kept]
        state :kept
        state :canceled
      end

    end
  end
end
