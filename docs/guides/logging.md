# Logging Guide

Familia provides comprehensive logging capabilities through a custom logger with TRACE level support and flexible database command logging middleware.

## Logger Configuration

### Default Logger

Familia uses a custom `FamiliaLogger` that extends Ruby's standard Logger:

```ruby
# Default logger with TRACE support
logger = Familia.logger
logger.trace "Detailed debugging information"
logger.debug "Standard debug message"
logger.info "General information"
```

### Custom Logger Replacement

Replace Familia's logger with any Logger-compatible object:

```ruby
# Use Rails logger
Familia.logger = Rails.logger

# Custom file logger with rotation
Familia.logger = Logger.new('familia.log', 'weekly')

# Syslog integration
require 'syslog/logger'
Familia.logger = Syslog::Logger.new('familia')
```

### Custom Formatters

Control log output formatting:

```ruby
custom_logger = Logger.new($stdout)
custom_logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end
Familia.logger = custom_logger
```

## Log Levels

### Standard Levels
- **INFO**: General informational messages
- **WARN**: Warning messages
- **ERROR**: Error messages
- **DEBUG**: Detailed debugging (controlled by `FAMILIA_DEBUG`)
- **FATAL**: Fatal errors

### TRACE Level
- **TRACE**: Extremely detailed debugging (requires both `FAMILIA_DEBUG` and `FAMILIA_TRACE`)
- Uses fiber-local storage to distinguish from DEBUG level
- Outputs with 'T' severity letter

## Environment Variables

Control logging behavior via environment variables:

- `FAMILIA_DEBUG`: Enable debug-level logging (`1`, `true`, `yes`)
- `FAMILIA_TRACE`: Enable trace-level logging (`1`, `true`, `yes`)

Both must be enabled for trace logging to work.

## Configuration Block

Enable debug mode programmatically:

```ruby
Familia.configure do |config|
  config.debug = true
end
```

## Structured Logging

Familia supports structured logging with key-value context:

```ruby
# Simple message
Familia.info "Connection established"

# With structured context
Familia.info "Pipeline executed", commands: 5, duration: 2340
# Output: "Pipeline executed commands=5 duration=2340"

Familia.debug "Cache lookup", key: "user:123", hit: true
Familia.error "Serialization failed", field: :email, error: e.message
```

## Database
 Command Logging

### DatabaseLogger Middleware

Familia includes `DatabaseLogger` middleware for Redis command logging:

```ruby
# Enable command logging (uses redis-rb middleware internally)
Familia.enable_database_logging = true

# Optional: Configure logger (uses Familia.logger by default)
DatabaseLogger.logger = Familia.logger
```

**Note**: Familia automatically registers the middleware with redis-rb when enabled. You work with `Redis.new` connections - the underlying `RedisClient` middleware registration is handled internally.

### Output Formats

**Standard Format:**
```
T, 20:43:09.843 [123] 0.001234 567μs > SET key value
```

**Structured Format:**
```ruby
DatabaseLogger.structured_logging = true
# Output: "Redis command cmd=SET args=[key, value] duration_ms=0.42 db=0"
```

### Sampling

Reduce log
 volume in high-traffic scenarios:

```ruby
# Log 10% of commands
DatabaseLogger.sample_rate = 0.1

# Log 1% of commands (production-friendly)
DatabaseLogger.sample_rate = 0.01

# Disable sampling (log everything)
DatabaseLogger.sample_rate = nil
```

### Command Capture

Capture commands for testing (unaffected by sampling):

```ruby
commands = DatabaseLogger.capture_commands do
  redis.set('key', 'value')
  redis.get('key')
end

puts commands.first.command  # => "SET key value"
puts commands.first.μs       # => 567 (microseconds)
```

## Default Logger Features

Familia's `FamiliaLogger` provides:

- **TRACE Level**: Distinct from DEBUG with 'T' severity marker
- **Structured Output**: `SEVERITY, HH:MM:SS.mmm MESSAGE` format
- **Fiber Support**: Thread/fiber-safe operation
- **Environment Control**: Automatic debug/trace enabling via env vars
- **LogFormatter**: Custom formatter with severity letters (T/D/I/W/E/F/U)

## Integration Examples

### Rails Integration
```ruby
# config/initializers/familia.rb
Familia.logger = Rails.logger
Familia.configure do |config|
  config.debug = Rails.env.development?
  config.enable_database_logging = Rails.env.development?
end
```

### Production Setup
```ruby
# Minimal logging with sampling
Familia.logger = Logger.new('familia.log')
Familia.logger.level = Logger::INFO
DatabaseLogger.sample_rate = 0.01  # 1% sampling
DatabaseLogger.structured_logging = true
```

This flexible logging system allows integration with existing logging infrastructure while maintaining Familia's specialized debugging capabilities.
