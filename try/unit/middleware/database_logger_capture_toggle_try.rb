# try/unit/middleware/database_logger_capture_toggle_try.rb
#
# frozen_string_literal: true

# Test DatabaseLogger.capture_enabled toggle and the zero-overhead fast path.
#
# capture_enabled is independent of sample_rate: sample_rate governs log output,
# capture_enabled governs whether commands are buffered (and whether timing /
# CommandMessage allocation happen at all). When capture is off, a command that
# is also not sampled for logging and has no registered instrumentation hook
# takes the fast path. Instrumentation hooks force the measured path so they
# keep firing at full rate.
#
# Covers:
# - capture_enabled accessor (default true, round-trips)
# - capture_enabled = false skips the buffer while logging still follows sample_rate
# - capture_enabled = true keeps full capture (backward compatible)
# - instrumentation hooks force the measured path even with capture off + sampled out
# - Familia::Instrumentation.hooks? predicate

require_relative '../../support/helpers/test_helpers'
require 'logger'
require 'stringio'
require 'concurrent-ruby'

# Force middleware (re)registration; earlier test files may disable logging.
Familia.connection_provider = nil
Familia.enable_database_logging = true
Familia.reconnect!

@original_logger = DatabaseLogger.logger
@original_sample_rate = DatabaseLogger.sample_rate
@original_capture = DatabaseLogger.capture_enabled
@original_structured = DatabaseLogger.structured_logging

# Quiet logger so trace output doesn't pollute test runs
@quiet_logger = Familia::FamiliaLogger.new(StringIO.new)
@quiet_logger.formatter = Familia::LogFormatter.new
@quiet_logger.level = Familia::FamiliaLogger::TRACE
DatabaseLogger.logger = @quiet_logger
DatabaseLogger.structured_logging = false
DatabaseLogger.sample_rate = nil
DatabaseLogger.clear_commands

## capture_enabled defaults to true
DatabaseLogger.capture_enabled
#=> true

## capture_enabled accessor round-trips to false
DatabaseLogger.capture_enabled = false
DatabaseLogger.capture_enabled
#=> false

## capture_enabled accessor round-trips back to true
DatabaseLogger.capture_enabled = true
DatabaseLogger.capture_enabled
#=> true

## capture_enabled=true captures every command (backward compatible default)
DatabaseLogger.capture_enabled = true
DatabaseLogger.sample_rate = nil
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  5.times { |i| dbclient.set("cap_on_#{i}", "v") }
end
commands.size >= 5
#=> true

## capture_enabled=false leaves the buffer empty while still logging at sample_rate
log_output = StringIO.new
test_logger = Familia::FamiliaLogger.new(log_output)
test_logger.formatter = Familia::LogFormatter.new
test_logger.level = Familia::FamiliaLogger::TRACE
DatabaseLogger.logger = test_logger
DatabaseLogger.clear_commands
DatabaseLogger.capture_enabled = false
DatabaseLogger.sample_rate = 0.5  # log every 2nd command
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))

dbclient = Familia.dbclient
20.times { |i| dbclient.set("cap_off_#{i}", "v") }

buffered = DatabaseLogger.commands.size
log_lines = log_output.string.lines.count
DatabaseLogger.logger = @quiet_logger
# Nothing buffered, but sampled logging still produced some (not all) lines
[buffered, log_lines.positive? && log_lines < 20]
#=> [0, true]

## capture_enabled=false with sample_rate=nil still logs every command, buffers none
log_output = StringIO.new
test_logger = Familia::FamiliaLogger.new(log_output)
test_logger.formatter = Familia::LogFormatter.new
test_logger.level = Familia::FamiliaLogger::TRACE
DatabaseLogger.logger = test_logger
DatabaseLogger.clear_commands
DatabaseLogger.capture_enabled = false
DatabaseLogger.sample_rate = nil

dbclient = Familia.dbclient
5.times { |i| dbclient.set("cap_off_nil_#{i}", "v") }

buffered = DatabaseLogger.commands.size
log_lines = log_output.string.lines.count
DatabaseLogger.logger = @quiet_logger
[buffered, log_lines >= 5]
#=> [0, true]

## capture_enabled=false skips capture for pipelined commands too
DatabaseLogger.clear_commands
DatabaseLogger.capture_enabled = false
DatabaseLogger.sample_rate = nil
dbclient = Familia.dbclient
4.times do
  dbclient.pipelined do |pipeline|
    pipeline.set("cap_off_pipe1", "v1")
    pipeline.set("cap_off_pipe2", "v2")
  end
end
DatabaseLogger.commands.size
#=> 0

## fast path: capture off, not sampled (logger nil), no hook -> no buffer, no crash
DatabaseLogger.clear_commands
DatabaseLogger.capture_enabled = false
DatabaseLogger.logger = nil          # should_log? returns false when logger is nil
DatabaseLogger.sample_rate = 0.01
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
dbclient = Familia.dbclient
result = dbclient.set("fast_path_key", "v")
buffered = DatabaseLogger.commands.size
DatabaseLogger.logger = @quiet_logger
[result, buffered]
#=> ["OK", 0]

## instrumentation hook forces the measured path even when capture off + sampled out
DatabaseLogger.clear_commands
DatabaseLogger.capture_enabled = false
DatabaseLogger.logger = nil          # should_log? false -> command not sampled
DatabaseLogger.sample_rate = 0.01
received = Concurrent::Array.new
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
Familia::Instrumentation.on_command { |cmd, _duration, _ctx| received << cmd }

dbclient = Familia.dbclient
dbclient.set("hook_forces_measure", "v")

# Clean up the hook so it doesn't leak into other tests
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
DatabaseLogger.logger = @quiet_logger
# Buffer stays empty (capture off) but the hook still fired (measured path)
[DatabaseLogger.commands.size, received.include?("set")]
#=> [0, true]

## hooks? is false when no command hooks are registered
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
Familia::Instrumentation.hooks?(:command)
#=> false

## hooks? is true once a command hook is registered
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
Familia::Instrumentation.on_command { |_cmd, _duration, _ctx| }
result = Familia::Instrumentation.hooks?(:command)
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
result
#=> true

## hooks? distinguishes hook types (pipeline empty while command registered)
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
Familia::Instrumentation.instance_variable_get(:@hooks)[:pipeline].clear
Familia::Instrumentation.on_command { |_cmd, _duration, _ctx| }
result = [Familia::Instrumentation.hooks?(:command), Familia::Instrumentation.hooks?(:pipeline)]
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
result
#=> [true, false]

# Teardown: restore original state
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
DatabaseLogger.logger = @original_logger
DatabaseLogger.sample_rate = @original_sample_rate
DatabaseLogger.capture_enabled = @original_capture
DatabaseLogger.structured_logging = @original_structured
DatabaseLogger.clear_commands
