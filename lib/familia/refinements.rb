# frozen_string_literal: true

require 'pathname'
require 'logger'

# Controls whether tracing is enabled via an environment variable
FAMILIA_TRACE = ENV.fetch('FAMILIA_TRACE', 'false').downcase

# LoggerTraceRefinement
#
# This module adds a 'trace' log level to the Ruby Logger class.
# It is enabled when the FAMILIA_TRACE environment variable is set to
# '1', 'true', or 'yes' (case-insensitive).
#
# @example Enabling trace logging
#   # Set environment variable
#   ENV['FAMILIA_TRACE'] = 'true'
#
#   # In your Ruby code
#   require 'logger'
#   using LoggerTraceRefinement
#
#   logger = Logger.new(STDOUT)
#   logger.trace("This is a trace message")
#
module LoggerTraceRefinement
  unless defined?(ENABLED)
    # Indicates whether trace logging is enabled
    ENABLED = %w[1 true yes].include?(FAMILIA_TRACE).freeze
    # The numeric level for trace logging (same as DEBUG)
    TRACE = 0
  end

  refine Logger do
    ##
    # Logs a message at the TRACE level.
    #
    # @param progname [String] The program name to include in the log message
    # @yield A block that evaluates to the message to log
    # @return [true] Always returns true
    #
    # @example Logging a trace message
    #   logger.trace("MyApp") { "Detailed trace information" }
    def trace(progname = nil, &block)
      Thread.current[:severity_letter] = 'T'
      add(LoggerTraceRefinement::TRACE, nil, progname, &block)
    ensure
      Thread.current[:severity_letter] = nil
    end
  end
end
