# lib/familia/logging.rb

require 'pathname'
require 'logger'

# Familia - Logbook
#
module Familia
  # Custom Logger subclass with TRACE level support.
  #
  # FamiliaLogger extends Ruby's standard Logger with a TRACE level for
  # extremely detailed debugging output. The TRACE level is numerically
  # equal to DEBUG (0) but distinguishes itself via a thread-local marker
  # that the LogFormatter uses to output 'T' instead of 'D'.
  #
  # @example Basic usage
  #   logger = Familia::FamiliaLogger.new($stderr)
  #   logger.level = Familia::FamiliaLogger::TRACE
  #   logger.trace "Detailed trace message"
  #   # => T, 10-05 20:43:09.843 pid:123 [456/789]: Detailed trace message
  #
  # @example With progname
  #   logger.trace("MyApp") { "Trace with progname" }
  #
  # @see Familia::LogFormatter
  #
  class FamiliaLogger < Logger
    # TRACE severity level (numerically equal to DEBUG=0).
    #
    # Uses the same numeric level as DEBUG but signals via thread-local
    # marker to output 'T' prefix instead of 'D'. This approach works
    # around Logger's limitation with negative severity values.
    #
    # Standard Logger levels: DEBUG=0, INFO=1, WARN=2, ERROR=3, FATAL=4, UNKNOWN=5
    TRACE = 0

    # Log a TRACE level message.
    #
    # This method behaves like the standard Logger methods (debug, info, etc.)
    # but outputs with a 'T' severity letter when used with LogFormatter.
    #
    # @param progname [String, nil] Program name to include in log output
    # @yield Block that returns the message to log (lazy evaluation)
    # @return [true] Always returns true
    #
    # @example Simple message
    #   logger.trace("Entering complex calculation")
    #
    # @example With block for lazy evaluation
    #   logger.trace { "Expensive: #{expensive_debug_info}" }
    #
    # @example With progname
    #   logger.trace("MyApp") { "Application trace" }
    #
    # @note Sets Fiber[:familia_trace_mode] during execution to
    #   signal LogFormatter to output 'T' instead of 'D'
    #
    def trace(progname = nil, &)
      # Store marker in thread-local to signal this is TRACE not DEBUG
      # Track whether we set the flag to avoid clearing it in nested calls
      was_already_tracing = Fiber[:familia_trace_mode]
      Fiber[:familia_trace_mode] = true
      add(TRACE, nil, progname, &)
    ensure
      # Only clear the flag if we set it (not already tracing)
      Fiber[:familia_trace_mode] = false unless was_already_tracing
    end
  end

  # Custom formatter for Familia logger output.
  #
  # LogFormatter produces structured log output with severity letters,
  # timestamps, process/thread/fiber IDs, and the log message.
  #
  # Output format:
  #   SEVERITY, MM-DD HH:MM:SS.mmm pid:PID [THREAD_ID/FIBER_ID]: MESSAGE
  #
  # @example Output
  #   I, 10-05 20:43:09.843 pid:12345 [67890/54321]: Connection established
  #   T, 10-05 20:43:10.123 pid:12345 [67890/54321]: [LOAD] redis -> user:123
  #
  # Severity letters:
  #   T = TRACE (when Fiber[:familia_trace_mode] is set, or level 0 when not using FamiliaLogger)
  #   D = DEBUG
  #   I = INFO
  #   W = WARN
  #   E = ERROR
  #   F = FATAL
  #   U = UNKNOWN
  #
  # @example Use with FamiliaLogger for TRACE support
  #   logger = Familia::FamiliaLogger.new($stderr)
  #   logger.formatter = Familia::LogFormatter.new
  #   logger.trace("Trace message")  # => T, ...
  #   logger.debug("Debug message")  # => D, ...
  #
  # @example Use with standard Logger (level 0 becomes 'T')
  #   logger = Logger.new($stderr)
  #   logger.formatter = Familia::LogFormatter.new
  #   logger.debug("Debug message")  # => T, ... (because DEBUG=0)
  #
  # @note When used with FamiliaLogger, checks Fiber[:familia_trace_mode] to
  #   distinguish TRACE from DEBUG. When used with standard Logger, treats
  #   level 0 as TRACE since DEBUG and TRACE share the same numeric level.
  #
  # @see FamiliaLogger#trace
  #
  class LogFormatter < Logger::Formatter
    # Severity string to letter mapping.
    #
    # Maps severity string labels to single-letter codes for compact output.
    # Note: TRACE is handled via Fiber check in #call for FamiliaLogger.
    SEVERITY_LETTERS = {
      'DEBUG' => 'D',
      'INFO' => 'I',
      'WARN' => 'W',
      'ERROR' => 'E',
      'FATAL' => 'F',
      'UNKNOWN' => 'U',
      'ANY' => 'T'  # ANY is Logger's label for severity < 0, treat as TRACE
    }.freeze

    # Format a log message with severity, timestamp, and context.
    #
    # @param severity [String] Severity label (e.g., "INFO", "DEBUG", "UNKNOWN")
    # @param datetime [Time] Timestamp of the log message
    # @param _progname [String] Program name (unused, kept for Logger compatibility)
    # @param msg [String] The log message
    # @return [String] Formatted log line with newline
    #
    # @example
    #   formatter = Familia::LogFormatter.new
    #   formatter.call("INFO", Time.now, nil, "Test message")
    #   # => "I, 10-05 20:43:09.843 pid:12345 [67890/54321]: Test message\n"
    #
    def call(severity, datetime, _progname, msg)
      # Check if we're in trace mode (TRACE uses same level as DEBUG but marks itself)
      # FamiliaLogger sets Fiber[:familia_trace_mode] when trace() is called
      severity_letter = if Fiber[:familia_trace_mode]
        'T'
      else
        SEVERITY_LETTERS.fetch(severity, severity[0])
      end

      utc_datetime = datetime.utc.strftime('%H:%M:%S.%3N')

      "#{severity_letter}, #{utc_datetime} #{msg}\n"
    end
  end

  # The Logging module provides logging capabilities for Familia.
  #
  # Familia uses a custom FamiliaLogger that extends the standard Ruby Logger
  # with a TRACE level for detailed debugging output.
  #
  # == Log Levels (from most to least verbose):
  # - TRACE: Extremely detailed debugging (controlled by FAMILIA_TRACE env var)
  # - DEBUG: Detailed debugging information
  # - INFO: General informational messages
  # - WARN: Warning messages
  # - ERROR: Error messages
  # - FATAL: Fatal errors that cause termination
  #
  # == Usage:
  #   # Use default logger
  #   Familia.info "Connection established"
  #   Familia.warn "Cache miss"
  #
  #   # Set custom logger
  #   Familia.logger = Logger.new('familia.log')
  #
  #   # Trace-level debugging (requires FAMILIA_TRACE=true)
  #   Familia.trace :LOAD, redis_client, "user:123", "from cache"
  #
  module Logging
    # Get the logger instance, initializing with defaults if not yet set
    #
    # @return [FamiliaLogger] the logger instance
    #
    # @example Set a custom logger
    #   Familia.logger = Logger.new('familia.log')
    #
    # @example Use the default logger
    #   Familia.logger.info "Connection established"
    #
    def logger
      @logger ||= FamiliaLogger.new($stderr).tap do |log|
        log.progname = name
        log.formatter = LogFormatter.new
      end
    end

    # Set a custom logger instance.
    #
    # Allows replacing the default FamiliaLogger with any Logger-compatible
    # object. Useful for integrating with application logging frameworks.
    #
    # @param new_logger [Logger] The logger to use
    # @return [Logger] The logger that was set
    #
    # @example Use Rails logger
    #   Familia.logger = Rails.logger
    #
    # @example Custom file logger
    #   Familia.logger = Logger.new('familia.log').tap do |log|
    #     log.level = Logger::INFO
    #   end
    #
    def logger=(new_logger)
      @logger = new_logger
    end

    # Log an informational message.
    #
    # @param msg [String] The message to log
    # @return [true]
    #
    # @example
    #   Familia.info "Redis connection established"
    #
    def info(msg)
      logger.info(msg)
    end

    # Log a warning message.
    #
    # @param msg [String] The message to log
    # @return [true]
    #
    # @example
    #   Familia.warn "Cache miss for key: user:123"
    #
    def warn(msg)
      logger.warn(msg)
    end

    # Log a debug message (only when Familia.debug? is true).
    #
    # Short for "log debug". Only outputs when FAMILIA_DEBUG environment
    # variable is set to '1' or 'true'.
    #
    # @param msg [String] The message to log
    # @return [true, nil] Returns true if logged, nil if debug disabled
    #
    # @example
    #   Familia.ld "Cache lookup for user:123"
    #   # Only outputs when FAMILIA_DEBUG=true
    #
    def ld(msg)
      logger.debug(msg) if Familia.debug?
    end

    # Log an error message.
    #
    # Short for "log error".
    #
    # @param msg [String] The message to log
    # @return [true]
    #
    # @example
    #   Familia.le "Failed to deserialize value: #{e.message}"
    #
    def le(msg)
      logger.error(msg)
    end

    # Logs a structured trace message for debugging Familia operations.
    #
    # This method only executes when both FAMILIA_TRACE and FAMILIA_DEBUG
    # environment variables are enabled.
    #
    # @param label [Symbol] A label for the trace message (e.g., :EXPAND,
    #   :FROMREDIS, :LOAD, :EXISTS).
    # @param instance_id [Object] The object instance being traced (e.g., Redis client)
    # @param ident [String] An identifier or key related to the operation being traced
    # @param extra_context [String, nil] Any extra details to include
    #
    # @return [nil]
    #
    # @example
    #   Familia.trace :LOAD, redis_client, "user:123", "from cache"
    #   # Output: T, 10-05 20:43:09.843 pid:123 [456/789]: [LOAD] #<Redis> -> user:123 <-from cache
    #
    # @note Controlled by FAMILIA_TRACE environment variable (set to '1', 'true', or 'yes')
    # @note The instance_id can be a Redis client, Redis::Future, or nil
    #
    def trace(label, instance_id = nil, ident = nil, extra_context = nil)
      return unless trace_enabled? && Familia.debug?

      ident_str = ident.nil? ? '<nil>' : ident.to_s
      logger.trace format('[%s] %s -> %s <-%s', label, instance_id, ident_str, extra_context)
    end

    private

    # Check if trace logging is enabled via FAMILIA_TRACE environment variable.
    #
    # Trace logging is enabled when FAMILIA_TRACE is set to '1', 'true',
    # or 'yes' (case-insensitive). Checks the environment variable on every
    # call to support dynamic changes in test environments.
    #
    # @return [Boolean] true if trace logging is enabled
    # @api private
    #
    def trace_enabled?
      %w[1 true yes].include?(ENV.fetch('FAMILIA_TRACE', 'false').downcase)
    end
  end
end
