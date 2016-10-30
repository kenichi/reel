# frozen_string_literals: true

module Reel

  module H2

    # http/2 psuedo-headers
    #
    AUTHORITY_KEY = ':authority'
    METHOD_KEY    = ':method'
    PATH_KEY      = ':path'
    SCHEME_KEY    = ':scheme'
    STATUS_KEY    = ':status'

    def self.verbose!
      @verbose = true
    end

    def self.verbose?
      @verbose = false unless defined?(@verbose)
      @verbose
    end

  end
end

require 'reel'
require 'reel/h2/connection'
require 'reel/h2/push_promise'
require 'reel/h2/response'
require 'reel/h2/server'
require 'reel/h2/stream_handler'
require 'reel/h2/upgrade'
