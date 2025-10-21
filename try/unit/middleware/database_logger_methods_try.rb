# try/unit/middleware/database_logger_methods_try.rb

# Test DatabaseLogger non-command methods and utilities
#
# This test file covers utility methods, configuration methods,
# and state management methods that don't involve command execution.
#
# Covers:
# - Configuration getters/setters (logger, max_commands, structured_logging, sample_rate)
# - Command storage methods (clear_commands, append_command, capture_commands)
# - Utility methods (index, now_in_μs, should_log?)
# - State introspection (commands, process_start)
# - Thread safety of command storage

require_relative '../../support/helpers/test_helpers'
require 'logger'
require 'stringio'
require 'concurrent-ruby'

@original_logger = DatabaseLogger.logger
@original_max_commands = DatabaseLogger.max_commands
@original_structured_logging = DatabaseLogger.structured_logging
@original_sample_rate = DatabaseLogger.sample_rate

# Clear initial state
DatabaseLogger.clear_commands
DatabaseLogger.logger = nil
DatabaseLogger.max_commands = 10_000
DatabaseLogger.structured_logging = false
DatabaseLogger.sample_rate = nil

## logger getter returns the current logger instance
test_logger = Logger.new(StringIO.new)
DatabaseLogger.logger = test_logger
DatabaseLogger.logger == test_logger
#=> true

## logger can be set to nil
DatabaseLogger.logger = nil
DatabaseLogger.logger
#=> nil

## max_commands getter returns the current max commands value
DatabaseLogger.max_commands = 5_000
DatabaseLogger.max_commands
#=> 5000

## max_commands can be set to different values
DatabaseLogger.max_commands = 1_000
DatabaseLogger.max_commands
#=> 1000

## structured_logging getter returns the current structured logging mode
DatabaseLogger.structured_logging = true
DatabaseLogger.structured_logging
#=> true

## structured_logging can be toggled
DatabaseLogger.structured_logging = false
DatabaseLogger.structured_logging
#=> false

## sample_rate getter returns the current sample rate
DatabaseLogger.sample_rate = 0.5
DatabaseLogger.sample_rate
#=> 0.5

## sample_rate can be set to nil
DatabaseLogger.sample_rate = nil
DatabaseLogger.sample_rate
#=> nil

## commands getter returns the captured commands array
DatabaseLogger.clear_commands
commands = DatabaseLogger.commands
commands.class
#=> Concurrent::Array

## commands array is initially empty after clear
DatabaseLogger.clear_commands
DatabaseLogger.commands.empty?
#=> true

## process_start returns a float timestamp
DatabaseLogger.process_start.class
#=> Float

## process_start is frozen
DatabaseLogger.process_start.frozen?
#=> true

## clear_commands returns nil and empties the commands array
DatabaseLogger.instance_variable_get(:@commands) << "test"
result = DatabaseLogger.clear_commands
[result, DatabaseLogger.commands.empty?]
#=> [nil, true]

## index returns the current count of commands
DatabaseLogger.clear_commands
DatabaseLogger.index
#=> 0

## index increases as commands are added
DatabaseLogger.clear_commands
msg = DatabaseLogger::CommandMessage.new("TEST", 100, 0.001)
DatabaseLogger.append_command(msg)
DatabaseLogger.index
#=> 1

## append_command adds a message to the commands array
DatabaseLogger.clear_commands
msg = DatabaseLogger::CommandMessage.new("SET key value", 500, 0.002)
result = DatabaseLogger.append_command(msg)
[DatabaseLogger.commands.size, result.last == msg]
#=> [1, true]

## append_command respects max_commands limit by shifting oldest
DatabaseLogger.max_commands = 3
DatabaseLogger.clear_commands
msg1 = DatabaseLogger::CommandMessage.new("CMD1", 100, 0.001)
msg2 = DatabaseLogger::CommandMessage.new("CMD2", 200, 0.002)
msg3 = DatabaseLogger::CommandMessage.new("CMD3", 300, 0.003)
msg4 = DatabaseLogger::CommandMessage.new("CMD4", 400, 0.004)

DatabaseLogger.append_command(msg1)
DatabaseLogger.append_command(msg2)
DatabaseLogger.append_command(msg3)
DatabaseLogger.append_command(msg4)

[DatabaseLogger.commands.size, DatabaseLogger.commands.first == msg2]
#=> [3, true]

## now_in_μs returns current time in microseconds
time1 = DatabaseLogger.now_in_μs
sleep(0.001)
time2 = DatabaseLogger.now_in_μs
time2 > time1
#=> true

## now_in_microseconds is an alias for now_in_μs
DatabaseLogger.method(:now_in_microseconds) == DatabaseLogger.method(:now_in_μs)
#=> true

## capture_commands yields and returns captured commands
DatabaseLogger.clear_commands
commands = DatabaseLogger.capture_commands do
  msg = DatabaseLogger::CommandMessage.new("GET key", 150, 0.001)
  DatabaseLogger.append_command(msg)
  msg2 = DatabaseLogger::CommandMessage.new("SET key2 value", 200, 0.002)
  DatabaseLogger.append_command(msg2)
end
commands.size
#=> 2

## capture_commands clears commands before capturing
DatabaseLogger.clear_commands
msg_before = DatabaseLogger::CommandMessage.new("BEFORE", 100, 0.001)
DatabaseLogger.append_command(msg_before)

commands = DatabaseLogger.capture_commands do
  msg = DatabaseLogger::CommandMessage.new("DURING", 150, 0.002)
  DatabaseLogger.append_command(msg)
end

[commands.size, commands.first.command]
#=> [1, "DURING"]

## capture_commands returns array snapshot, not live reference
DatabaseLogger.clear_commands
commands = DatabaseLogger.capture_commands do
  msg = DatabaseLogger::CommandMessage.new("TEST", 100, 0.001)
  DatabaseLogger.append_command(msg)
end

# Add another command after capture
msg2 = DatabaseLogger::CommandMessage.new("AFTER", 200, 0.002)
DatabaseLogger.append_command(msg2)

[commands.size, DatabaseLogger.commands.size]
#=> [1, 2]

## should_log? returns true when sample_rate is nil
DatabaseLogger.sample_rate = nil
DatabaseLogger.logger = Logger.new(StringIO.new)
DatabaseLogger.should_log?
#=> true

## should_log? returns false when logger is nil regardless of sample_rate
DatabaseLogger.sample_rate = 1.0
DatabaseLogger.logger = nil
DatabaseLogger.should_log?
#=> false

## should_log? uses atomic counter for thread-safe sampling
DatabaseLogger.sample_rate = 0.5  # 50% sampling
DatabaseLogger.logger = Logger.new(StringIO.new)
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))

# Test deterministic sampling pattern
results = 10.times.map { DatabaseLogger.should_log? }
results.count(true)
#=> 5

## should_log? sampling is deterministic and consistent
DatabaseLogger.sample_rate = 0.25  # 25% sampling (every 4th)
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))

results = 12.times.map { DatabaseLogger.should_log? }
results.count(true)
#=> 3

## CommandMessage can be created with command, duration, timeline
msg = DatabaseLogger::CommandMessage.new("SET key value", 1500, 0.123456)
[msg.command, msg.μs, msg.timeline]
#=> ["SET key value", 1500, 0.123456]

## CommandMessage.inspect formats nicely
msg = DatabaseLogger::CommandMessage.new("GET key", 2500, 1.234567)
msg.inspect
#=> "1.234567 2500μs > GET key"

## CommandMessage.to_a returns deconstructed array
msg = DatabaseLogger::CommandMessage.new("DEL key1 key2", 750, 2.345678)
msg.to_a
#=> ["DEL key1 key2", 750, 2.345678]

## Thread safety: append_command is thread-safe with concurrent access
# Reset max_commands to allow all 100 commands
DatabaseLogger.max_commands = 1000
DatabaseLogger.clear_commands
threads = 10.times.map do |i|
  Thread.new do
    10.times do |j|
      msg = DatabaseLogger::CommandMessage.new("THREAD#{i}_CMD#{j}", 100, 0.001)
      DatabaseLogger.append_command(msg)
    end
  end
end

threads.each(&:join)
DatabaseLogger.commands.size
#=> 100

# Restore original state
DatabaseLogger.logger = @original_logger
DatabaseLogger.max_commands = @original_max_commands
DatabaseLogger.structured_logging = @original_structured_logging
DatabaseLogger.sample_rate = @original_sample_rate
DatabaseLogger.clear_commands
