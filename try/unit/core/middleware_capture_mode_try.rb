# try/unit/core/middleware_capture_mode_try.rb
#
# frozen_string_literal: true

# Test DatabaseLogger.capture_mode buffer-capture gating (issue #233)
#
# sample_rate only governs log output. capture_mode independently governs
# whether each command is captured into the buffer and whether the timing /
# CommandMessage overhead is paid at all:
#
#   :all     -> capture every command          (default, backward compatible)
#   :sampled -> capture only sampled commands  (overhead follows sample_rate)
#   :none    -> capture nothing                (log-only, lowest overhead)
#
# Covers:
# - capture_mode configuration and validation
# - should_capture? decision logic per mode
# - Integration with call / call_pipelined for each mode
# - Zero-overhead path skips timing + CommandMessage for non-sampled commands
# - Instrumentation hooks still receive timing data regardless of capture_mode

require_relative '../../support/helpers/test_helpers'
require 'logger'
require 'stringio'

# Setup: Reset DatabaseLogger and Familia connection state, mirroring
# middleware_sampling_try.rb so the middleware is freshly registered.
Familia.connection_provider = nil
Familia.enable_database_logging = true
Familia.reconnect!
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = nil
DatabaseLogger.structured_logging = false
DatabaseLogger.capture_mode = :all
@original_logger = DatabaseLogger.logger

## capture_mode defaults to :all
DatabaseLogger.capture_mode
#=> :all

## capture_mode can be set to :sampled
DatabaseLogger.capture_mode = :sampled
DatabaseLogger.capture_mode
#=> :sampled

## capture_mode can be set to :none
DatabaseLogger.capture_mode = :none
DatabaseLogger.capture_mode
#=> :none

## capture_mode can be reset to :all
DatabaseLogger.capture_mode = :none
DatabaseLogger.capture_mode = :all
DatabaseLogger.capture_mode
#=> :all

## capture_mode rejects unknown symbols with ArgumentError
DatabaseLogger.capture_mode = :everything
#=!> ArgumentError

## capture_mode rejects nil with ArgumentError
DatabaseLogger.capture_mode = nil
#=!> ArgumentError

## rejected assignment leaves the previous mode intact
DatabaseLogger.capture_mode = :sampled
begin
  DatabaseLogger.capture_mode = :bogus
rescue ArgumentError
  # ignored
end
result = DatabaseLogger.capture_mode
DatabaseLogger.capture_mode = :all
result
#=> :sampled

## CAPTURE_MODES lists the three supported modes
DatabaseLogger::CAPTURE_MODES
#=> [:all, :sampled, :none]

## should_capture? always true in :all mode (independent of sampling decision)
DatabaseLogger.capture_mode = :all
[DatabaseLogger.should_capture?(true), DatabaseLogger.should_capture?(false)]
#=> [true, true]

## should_capture? follows the sampling decision in :sampled mode
DatabaseLogger.capture_mode = :sampled
[DatabaseLogger.should_capture?(true), DatabaseLogger.should_capture?(false)]
#=> [true, false]

## should_capture? always false in :none mode
DatabaseLogger.capture_mode = :none
[DatabaseLogger.should_capture?(true), DatabaseLogger.should_capture?(false)]
#=> [false, false]

## :all mode captures every command even when only 10% is logged
DatabaseLogger.capture_mode = :all
DatabaseLogger.sample_rate = 0.1
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  10.times { |i| dbclient.set("capall_#{i}", "value") }
end
commands.count
#=> 10

## :none mode captures nothing even when logging everything (sample_rate nil)
DatabaseLogger.capture_mode = :none
DatabaseLogger.sample_rate = nil
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  10.times { |i| dbclient.set("capnone_#{i}", "value") }
end
commands.count
#=> 0

## :none mode still emits log output per sample_rate (log-only mode)
@log_output = StringIO.new
@none_logger = Familia::FamiliaLogger.new(@log_output)
@none_logger.formatter = Familia::LogFormatter.new
@none_logger.level = Familia::FamiliaLogger::TRACE
DatabaseLogger.logger = @none_logger
DatabaseLogger.capture_mode = :none
DatabaseLogger.sample_rate = nil  # log everything
dbclient = Familia.dbclient
DatabaseLogger.capture_commands do
  5.times { |i| dbclient.set("nonelog_#{i}", "value") }
end
log_lines = @log_output.string.lines.count
DatabaseLogger.logger = @original_logger
log_lines
#=> 5

## :sampled mode with sample_rate nil captures every command
DatabaseLogger.capture_mode = :sampled
DatabaseLogger.sample_rate = nil
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  8.times { |i| dbclient.set("sampnil_#{i}", "value") }
end
commands.count
#=> 8

## :sampled mode at 50% captures roughly half the commands
DatabaseLogger.capture_mode = :sampled
DatabaseLogger.sample_rate = 0.5  # every 2nd command
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  10.times { |i| dbclient.set("samp50_#{i}", "value") }
end
commands.count
#=> 5

## :sampled mode captures pipelines per sample_rate
DatabaseLogger.capture_mode = :sampled
DatabaseLogger.sample_rate = 0.5  # every 2nd pipeline
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  4.times do
    dbclient.pipelined do |pipeline|
      pipeline.set("cappipe_k1", "v1")
      pipeline.set("cappipe_k2", "v2")
    end
  end
end
commands.count
#=> 2

## captured commands in :sampled mode still carry full timing metadata
DatabaseLogger.capture_mode = :sampled
DatabaseLogger.sample_rate = nil
dbclient = Familia.dbclient
commands = DatabaseLogger.capture_commands do
  dbclient.set("sampmeta_key", "value")
end
cmd = commands.first
[cmd.command.class, cmd.μs.class, cmd.timeline.class]
#=> [String, Integer, Float]

## sample counter still advances once per command in :none mode
# The zero-overhead path skips timing/capture but the sampling decision (a
# single atomic increment) must still run so the 1/N distribution holds.
DatabaseLogger.capture_mode = :none
DatabaseLogger.sample_rate = 1.0
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))
counter_start = DatabaseLogger.instance_variable_get(:@sample_counter).value
dbclient = Familia.dbclient
10.times { |i| dbclient.set("nonectr_#{i}", "value") }
counter_end = DatabaseLogger.instance_variable_get(:@sample_counter).value
counter_end - counter_start
#=> 10

## instrumentation command hooks receive timing data even in :none mode
# capture is disabled and sampling is 1%, but a registered hook forces the
# measured path so duration data is still collected and delivered.
DatabaseLogger.capture_mode = :none
DatabaseLogger.sample_rate = 0.01
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))
@fired = Concurrent::Array.new
Familia::Instrumentation.on_command { |cmd, duration, _ctx| @fired << [cmd, duration] }
dbclient = Familia.dbclient
DatabaseLogger.capture_commands do
  5.times { |i| dbclient.set("instr_#{i}", "value") }
end
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
fired_count = @fired.count
durations_numeric = @fired.all? { |_cmd, duration| duration.is_a?(Numeric) }
[fired_count, durations_numeric]
#=> [5, true]

# Teardown: Reset to defaults so other middleware test files see clean state
DatabaseLogger.logger = @original_logger
DatabaseLogger.capture_mode = :all
DatabaseLogger.sample_rate = nil
DatabaseLogger.structured_logging = false
DatabaseLogger.instance_variable_set(:@sample_counter, Concurrent::AtomicFixnum.new(0))
DatabaseLogger.clear_commands
Familia::Instrumentation.instance_variable_get(:@hooks)[:command].clear
