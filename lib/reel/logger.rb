require 'logger'

module Reel
  module Logger
    module_function

    def logger=(logger)
      @logger = logger
    end

    def logger
      @logger ||= ::Logger.new STDERR
    end

    def level=(level)
      logger.level = ::Logger.const_get(level.to_s.upcase)
    end

    def debug(msg); logger.debug(msg); end
    def info(msg);  logger.info(msg);  end
    def warn(msg);  logger.warn(msg);  end
    def error(msg); logger.error(msg); end
  end
end

# default to sane logging
Reel::Logger.logger.level = ::Logger::INFO
