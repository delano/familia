# frozen_string_literal: true

require 'pathname'
require 'logger'

# Controls whether tracing is enabled via an environment variable
FAMILIA_TRACE = ENV.fetch('FAMILIA_TRACE', 'false').downcase

# FlexibleHashAccess
#
# This module provides a refinement for the Hash class to allow flexible access
# to hash keys using either strings or symbols interchangeably for reading values.
#
# Note: This refinement only affects reading from the hash. Writing to the hash
# maintains the original key type.
#
# @example Using the refinement
#   using FlexibleHashAccess
#
#   h = { name: "Alice", "age" => 30 }
#   h[:name]   # => "Alice"
#   h["name"]  # => "Alice"
#   h[:age]    # => 30
#   h["age"]   # => 30
#
#   h["job"] = "Developer"
#   h[:job]    # => "Developer"
#   h["job"]   # => "Developer"
#
#   h[:salary] = 75000
#   h[:salary] # => 75000
#   h["salary"] # => nil (original key type is preserved)
#
module FlexibleHashAccess
  refine Hash do
    ##
    # Retrieves a value from the hash using either a string or symbol key.
    #
    # @param key [String, Symbol] The key to look up
    # @return [Object, nil] The value associated with the key, or nil if not found
    def [](key)
      super(key.to_s) || super(key.to_sym)
    end
  end
end

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
  # Indicates whether trace logging is enabled
  ENABLED = %w[1 true yes].include?(FAMILIA_TRACE)

  # The numeric level for trace logging (same as DEBUG)
  TRACE = 0 unless defined?(TRACE)

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
