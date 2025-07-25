# lib/familia/logging.rb

require 'pathname'
require 'logger'

module Familia
  @logger = Logger.new($stdout)
  @logger.progname = name
  @logger.formatter = proc do |severity, datetime, progname, msg|
    severity_letter = severity[0]  # Get the first letter of the severity
    pid = Process.pid
    thread_id = Thread.current.object_id
    full_path, line = caller[4].split(":")[0..1]
    parent_path = Pathname.new(full_path).ascend.find { |p| p.basename.to_s == 'familia' }
    relative_path = full_path.sub(parent_path.to_s, 'familia')
    utc_datetime = datetime.utc.strftime("%m-%d %H:%M:%S.%6N")

    # Get the severity letter from the thread local variable or use
    # the default. The thread local variable is set in the trace
    # method in the LoggerTraceRefinement module. The name of the
    # variable `severity_letter` is arbitrary and could be anything.
    severity_letter = Thread.current[:severity_letter] || severity_letter

    "#{severity_letter}, #{utc_datetime} #{pid} #{thread_id}: #{msg}  [#{relative_path}:#{line}]\n"
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
  #   LoggerTraceRefinement is used.
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
  # To use the Logging module, you need to include the LoggerTraceRefinement module
  # and use the `using` keyword to enable the refinement. This will add the TRACE
  # log level and the trace method to the Logger class.
  #
  # Example:
  #   require 'logger'
  #
  #   module LoggerTraceRefinement
  #     refine Logger do
  #       TRACE = 0
  #
  #       def trace(progname = nil, &block)
  #         add(TRACE, nil, progname, &block)
  #       end
  #     end
  #   end
  #
  #   using LoggerTraceRefinement
  #
  #   logger = Logger.new(STDOUT)
  #   logger.trace("This is a trace message")
  #   logger.debug("This is a debug message")
  #   logger.info("This is an info message")
  #   logger.warn("This is a warning message")
  #   logger.error("This is an error message")
  #   logger.fatal("This is a fatal message")
  #
  # In this example, the LoggerTraceRefinement module is defined with a refinement
  # for the Logger class. The TRACE constant and trace method are added to the Logger
  # class within the refinement. The `using` keyword is used to apply the refinement
  # in the scope where it's needed.
  #
  # == Conditions:
  # The trace method and TRACE log level are only available if the LoggerTraceRefinement
  # module is used with the `using` keyword. Without this, the Logger class will not
  # have the trace method or the TRACE log level.
  #
  # == Minimum Ruby Version:
  # This module requires Ruby 2.0.0 or later to use refinements.
  #
  module Logging
    attr_reader :logger

    # Gives our logger the ability to use our trace method.
    using LoggerTraceRefinement if LoggerTraceRefinement::ENABLED

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
    # @param redis_instance [Redis, Redis::Future, nil] The Database instance or
    #   Future being used.
    # @param ident [String] An identifier or key related to the operation being
    #   traced.
    # @param context [Array<String>, String, nil] The calling context, typically
    #   obtained from `caller` or `caller.first`. Default is nil.
    #
    # @example
    #   Familia.trace :LOAD, Familia.redis(uri), objkey, caller(1..1) if
    #   Familia.debug?
    #
    # @return [nil]
    #
    # @note This method only executes if LoggerTraceRefinement::ENABLED is true.
    # @note The redis_instance can be a Database object, Redis::Future (used in
    #   pipelined and multi blocks), or nil (when the redis connection isn't
    #   relevant).
    #
    def trace(label, redis_instance, ident, context = nil)
      return unless LoggerTraceRefinement::ENABLED

      # Usually redis_instance is a Database object, but it could be
      # a Redis::Future which is what is used inside of pipelined
      # and multi blocks. In some contexts it's nil where the
      # redis connection isn't relevant.
      instance_id = if redis_instance
        case redis_instance
        when Redis
          redis_instance.id.respond_to?(:to_s) ? redis_instance.id.to_s : redis_instance.class.name
        when Redis::Future
          "Redis::Future"
        else
          redis_instance.class.name
        end
      end

      codeline = if context
                   context = [context].flatten
                   context.reject! { |line| line =~ %r{lib/familia} }
                   context.first
                 end

      @logger.trace format('[%s] %s -> %s <- at %s', label, instance_id, ident, codeline)
    end

  end
end


__END__


### Example 1: Basic Logging
```ruby
require 'logger'

logger = Logger.new($stdout)
logger.info("This is an info message")
logger.warn("This is a warning message")
logger.error("This is an error message")
```

### Example 2: Setting Log Level
```ruby
require 'logger'

logger = Logger.new($stdout)
logger.level = Logger::WARN

logger.debug("This is a debug message") # Will not be logged
logger.info("This is an info message")  # Will not be logged
logger.warn("This is a warning message")
logger.error("This is an error message")
```

### Example 3: Customizing Log Format
```ruby
require 'logger'

logger = Logger.new($stdout)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{datetime}: #{severity} - #{msg}\n"
end

logger.info("This is an info message")
logger.warn("This is a warning message")
logger.error("This is an error message")
```

### Example 4: Logging with a Program Name
```ruby
require 'logger'

logger = Logger.new($stdout)
logger.progname = 'Familia'

logger.info("This is an info message")
logger.warn("This is a warning message")
logger.error("This is an error message")
```

### Example 5: Logging with a Block
```ruby
require 'logger'

# Calling any of the methods above with a block
#   (affects only the one entry).
#   Doing so can have two benefits:
#
#   - Context: the block can evaluate the entire program context
#     and create a context-dependent message.
#   - Performance: the block is not evaluated unless the log level
#     permits the entry actually to be written:
#
#       logger.error { my_slow_message_generator }
#
#     Contrast this with the string form, where the string is
#     always evaluated, regardless of the log level:
#
#       logger.error("#{my_slow_message_generator}")
logger = Logger.new($stdout)

logger.info { "This is an info message" }
logger.warn { "This is a warning message" }
logger.error { "This is an error message" }
```
