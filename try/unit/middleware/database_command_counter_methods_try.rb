# try/unit/middleware/database_command_counter_methods_try.rb

# Test DatabaseCommandCounter non-command methods and utilities
#
# This test file covers utility methods, configuration methods,
# and state management methods that don't involve command execution.
#
# Covers:
# - Counter methods (count, reset, increment, count_commands)
# - Configuration (skip_commands)
# - Utility methods (skip_command?)
# - Thread safety of atomic counter

require_relative '../../support/helpers/test_helpers'
require 'concurrent-ruby'

@original_count = DatabaseCommandCounter.count

# Clear initial state
DatabaseCommandCounter.reset

## count returns the current command count
DatabaseCommandCounter.reset
DatabaseCommandCounter.count
#=> 0

## reset sets count to zero
DatabaseCommandCounter.increment
DatabaseCommandCounter.increment
DatabaseCommandCounter.reset
DatabaseCommandCounter.count
#=> 0

## reset returns zero
result = DatabaseCommandCounter.reset
result
#=> 0

## increment increases the count by 1
DatabaseCommandCounter.reset
DatabaseCommandCounter.increment
DatabaseCommandCounter.count
#=> 1

## increment returns the new count
DatabaseCommandCounter.reset
result = DatabaseCommandCounter.increment
result
#=> 1

## increment can be called multiple times
DatabaseCommandCounter.reset
3.times { DatabaseCommandCounter.increment }
DatabaseCommandCounter.count
#=> 3

## skip_commands returns a Set with default skipped commands
DatabaseCommandCounter.skip_commands.class
#=> Set

## skip_commands includes SELECT by default
DatabaseCommandCounter.skip_commands.include?("SELECT")
#=> true

## skip_commands is frozen for immutability
DatabaseCommandCounter.skip_commands.frozen?
#=> true

## skip_command? returns true for commands in skip_commands
DatabaseCommandCounter.skip_command?(["SELECT", "0"])
#=> true

## skip_command? returns false for commands not in skip_commands
DatabaseCommandCounter.skip_command?(["SET", "key", "value"])
#=> false

## skip_command? handles command array properly
DatabaseCommandCounter.skip_command?(["GET", "key"])
#=> false

## skip_command? is case insensitive
DatabaseCommandCounter.skip_command?(["select", "0"])
#=> true

## count_commands captures count difference in block
DatabaseCommandCounter.reset
initial_count = DatabaseCommandCounter.count
commands_executed = DatabaseCommandCounter.count_commands do
  5.times { DatabaseCommandCounter.increment }
end
commands_executed
#=> 5

## count_commands works with empty block
DatabaseCommandCounter.reset
commands_executed = DatabaseCommandCounter.count_commands do
  # No commands
end
commands_executed
#=> 0

## count_commands captures count difference with existing count
DatabaseCommandCounter.reset
5.times { DatabaseCommandCounter.increment }  # Existing commands
commands_executed = DatabaseCommandCounter.count_commands do
  3.times { DatabaseCommandCounter.increment }  # New commands in block
end
commands_executed
#=> 3

## Thread safety: increment is thread-safe with concurrent access
DatabaseCommandCounter.reset
threads = 10.times.map do |i|
  Thread.new do
    10.times { DatabaseCommandCounter.increment }
  end
end

threads.each(&:join)
DatabaseCommandCounter.count
#=> 100

## Thread safety: count_commands is thread-safe
DatabaseCommandCounter.reset
result = DatabaseCommandCounter.count_commands do
  threads = 5.times.map do
    Thread.new do
      10.times { DatabaseCommandCounter.increment }
    end
  end
  threads.each(&:join)
end
result
#=> 50

# Restore original state (if needed)
DatabaseCommandCounter.reset
