# rubocop:disable all

require 'logger'

module Familia
  @logger = Logger.new($stdout)
  @logger.progname = name

  module Logging

    def info(*msg)
      @logger.info(*msg)
    end

    def warn(*msg)
      @logger.warn(*msg)
    end

    def ld(*msg)
      @logger.debug(*msg)
    end

    def le(*msg)
      @logger.error(*msg)
    end

    # Logs a trace message for debugging purposes if Familia.debug? is true.
    #
    # @param label [Symbol] A label for the trace message (e.g., :EXPAND,
    #   :FROMREDIS, :LOAD, :EXISTS).
    # @param redis_instance [Object] The Redis instance being used.
    # @param ident [String] An identifier or key related to the operation being
    #   traced.
    # @param context [Array<String>, String, nil] The calling context, typically
    #   obtained from `caller` or `caller.first`. Default is nil.
    #
    # @example
    #   Familia.trace :LOAD, Familia.redis(uri), objkey, caller if Familia.debug?

    #
    # @return [nil]
    def trace(label, redis_instance, ident, context = nil)
      return unless Familia.debug?

      codeline = if context
                   context = [context].flatten
                   context.reject! { |line| line =~ %r{lib/familia} }
                   context.first
                 end
      info format('[%s] -> %s <- %s %s', label, codeline, redis_instance.id, ident)
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
logger.progname = 'MyApp'

logger.info("This is an info message")
logger.warn("This is a warning message")
logger.error("This is an error message")
```

### Example 5: Logging with a Block
```ruby
require 'logger'

logger = Logger.new($stdout)

logger.info { "This is an info message" }
logger.warn { "This is a warning message" }
logger.error { "This is an error message" }
```

These examples demonstrate various ways to use the [`Logger`](command:_github.copilot.openSymbolFromReferences?%5B%22%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22%2FUsers%2Fd%2FProjects%2Fopensource%2Fd%2Ffamilia%2Flib2%2Ffamilia%2Flogging.rb%22%2C%22external%22%3A%22file%3A%2F%2F%2FUsers%2Fd%2FProjects%2Fopensource%2Fd%2Ffamilia%2Flib2%2Ffamilia%2Flogging.rb%22%2C%22path%22%3A%22%2FUsers%2Fd%2FProjects%2Fopensource%2Fd%2Ffamilia%2Flib2%2Ffamilia%2Flogging.rb%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A3%2C%22character%22%3A9%7D%7D%5D%5D "Go to definition") class in Ruby to log messages to the standard output.
