module Reel
  module H2
    class PushPromise

      GET    = 'GET'
      STATUS = '200' # TODO: can one push promise a redirect? 🤔

      attr_reader :content_length, :path, :push_stream

      # build a new +PushPromise+ for the path, with the headers and body given
      #
      def initialize path, body_or_headers = {}, body = nil
        @path = path
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
          Reel::H2::PATH_KEY      => @path,
          Reel::H2::SCHEME_KEY    => headers.delete(Reel::H2::SCHEME_KEY)
        }

        @content_length = @body.bytesize.to_s

        @push_headers = {
          Reel::H2::STATUS_KEY           => STATUS,
          Reel::Response::CONTENT_LENGTH => @content_length
        }.merge headers

        @fsm = FSM.new
      end

      # create a new promise stream from +stream+, send the headers and set
      # +@push_stream+ from the callback
      #
      def make_on! stream
        return unless @fsm.state == :init
        @fsm.transition :made
        stream.promise(@promise_headers) do |push|
          push.headers @push_headers
          @push_stream = push
        end
        self
      end

      # deliver the body for thise promise
      #
      def keep! size = nil
        return unless @fsm.state == :made
        @fsm.transition :kept
        if size.nil?
          @push_stream.data @body
        else
          body = @body

          if body.bytesize > size
            body = @body.dup
            while body.bytesize > size
              @push_stream.data body.slice!(0, size), end_stream: false
              yield if block_given?
            end
          else
            yield if block_given?
          end

          @push_stream.data body
        end
      end

      # cancel this promise, most likely due to a RST_STREAM frame from the
      # client (already in cache, etc...)
      #
      # TODO: implement RST_STREAM handling to cancel promises?
      #
      def cancel!
        @fsm.transition :canceled
      end

      # simple state machine to guarantee promise process
      #
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
