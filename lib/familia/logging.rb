# lib/familia/logging.rb

require 'pathname'
require 'logger'

module Familia
  @logger = Logger.new($stdout)
  @logger.progname = name
  @logger.formatter = proc do |severity, datetime, _progname, msg|
    severity_letter = severity[0] # Get the first letter of the severity
    pid = Process.pid
    thread_id = Thread.current.object_id
    fiber_id = Fiber.current.object_id
    full_path, line = caller(5..5).first.split(':')[0..1]
    parent_path = Pathname.new(full_path).ascend.find { |p| p.basename.to_s == 'familia' }
    relative_path = full_path.sub(parent_path.to_s, 'familia')
    utc_datetime = datetime.utc.strftime('%m-%d %H:%M:%S.%6N')

    # Get the severity letter from the thread local variable or use
    # the default. The thread local variable is set in the trace
    # method in the Familia::Refinements::LoggerTrace module. The name of the
    # variable `severity_letter` is arbitrary and could be anything.
    severity_letter = Fiber[:severity_letter] || severity_letter

    "#{severity_letter}, #{utc_datetime} #{pid} #{thread_id}/#{fiber_id}: #{msg}  [#{relative_path}:#{line}]\n"
  end

  # The Logging module provides a set of methods and constants for logging messages
  # at various levels of severity. It is designed to be used with the Ruby Logger class
  # to facilitate logging in applications.
  #
  # == Constants:
  # Logger::TRACE::
  #   A custom log level for trace messages, typically used for very detailed
  #   debugging information.
  #
  # == Methods:
  # trace::
  #   Logs a message at the TRACE level. This method is only available if the
  #   Familia::Refinements::LoggerTrace is used.
  #
  # debug::
  #   Logs a message at the DEBUG level. This is used for low-level system information
  #   for debugging purposes.
  #
  # info::
  #   Logs a message at the INFO level. This is used for general information about
  #   system operation.
  #
  # warn::
  #   Logs a message at the WARN level. This is used for warning messages, typically
  #   for non-critical issues that require attention.
  #
  # error::
  #   Logs a message at the ERROR level. This is used for error messages, typically
  #   for critical issues that require immediate attention.
  #
  # fatal::
  #   Logs a message at the FATAL level. This is used for very severe error events
  #   that will presumably lead the application to abort.
  #
  # == Usage:
  # To use the Logging module, you need to include the Familia::Refinements::LoggerTrace module
  # and use the `using` keyword to enable the refinement. This will add the TRACE
  # log level and the trace method to the Logger class.
  #
  # Example:
  #   require 'logger'
  #
  #   module Familia::Refinements::LoggerTrace
  #     refine Logger do
  #       TRACE = 0
  #
  #       def trace(progname = nil, &block)
  #         add(TRACE, nil, progname, &block)
  #       end
  #     end
  #   end
  #
  #   using Familia::Refinements::LoggerTrace
  #
  #   logger = Logger.new(STDOUT)
  #   logger.trace("This is a trace message")
  #   logger.debug("This is a debug message")
  #   logger.info("This is an info message")
  #   logger.warn("This is a warning message")
  #   logger.error("This is an error message")
  #   logger.fatal("This is a fatal message")
  #
  # In this example, the Familia::Refinements::LoggerTrace module is defined with a refinement
  # for the Logger class. The TRACE constant and trace method are added to the Logger
  # class within the refinement. The `using` keyword is used to apply the refinement
  # in the scope where it's needed.
  #
  # == Conditions:
  # The trace method and TRACE log level are only available if the Familia::Refinements::LoggerTrace
  # module is used with the `using` keyword. Without this, the Logger class will not
  # have the trace method or the TRACE log level.
  #
  # == Minimum Ruby Version:
  # This module requires Ruby 2.0.0 or later to use refinements.
  #
  module Logging
    attr_reader :logger

    # Gives our logger the ability to use our trace method.
    using Familia::Refinements::LoggerTrace if Familia::Refinements::LoggerTrace::ENABLED

    def info(*msg)
      @logger.info(*msg)
    end

    def warn(*msg)
      @logger.warn(*msg)
    end

    def ld(*msg)
      return unless Familia.debug?

      @logger.debug(*msg)
    end

    def le(*msg)
      @logger.error(*msg)
    end

    # Logs a trace message for debugging purposes if Familia.debug? is true.
    #
    # @param label [Symbol] A label for the trace message (e.g., :EXPAND,
    #   :FROMREDIS, :LOAD, :EXISTS).
    # @param instance_id
    # @param ident [String] An identifier or key related to the operation being
    #   traced.
    # @param extra_context [Array<String>, String, nil] Any extra details to include.
    #
    # @example Familia.trace :LOAD, Familia.dbclient(uri), objkey if Familia.debug?
    #
    # @return [nil]
    #
    # @note This method only executes if Familia::Refinements::LoggerTrace::ENABLED is true.
    # @note The dbclient can be a Database object, Redis::Future (used in
    #   pipelined and multi blocks), or nil (when the database connection isn't
    #   relevant).
    #
    def trace(label, instance_id = nil, ident = nil, extra_context = nil)
      return unless Familia::Refinements::LoggerTrace::ENABLED

      # Let the other values show nothing when nil, but make it known for the focused value
      ident_str = (ident.nil? ? '<nil>' : ident).to_s
      @logger.trace format('[%s] %s -> %s <-%s', label, instance_id, ident_str, extra_context)
    end
  end
end
