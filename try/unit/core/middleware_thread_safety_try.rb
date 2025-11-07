# try/unit/core/middleware_thread_safety_try.rb
#
# frozen_string_literal: true

# Thread Safety Tests for DatabaseLogger Middleware
#
# These tests specifically target potential race conditions and concurrency issues
# in the DatabaseLogger middleware that could lead to nil entries in the @commands array.
#
# Covers:
# - Concurrent append_command operations
# - Thread-safe pipeline command logging
# - Mixed operation types under contention
# - Sampling counter atomicity
# - Rapid sequential calls within threads
# - clear_commands during active logging
#
# Background:
# An intermittent NoMethodError was observed where .command was called on nil
# during teardown of middleware_sampling_try.rb. The error suggests potential
# corruption of the @commands Concurrent::Array, possibly due to race conditions
# between append_command, clear_commands, or middleware state management.

require_relative '../../support/helpers/test_helpers'
require 'concurrent'

# Setup: Reset DatabaseLogger and ensure middleware is registered
Familia.connection_provider = nil
Familia.enable_database_logging = true
Familia.reconnect!
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = nil
DatabaseLogger.structured_logging = false

## DatabaseLogger.append_command is thread-safe under concurrent access from 50 threads
# First verify middleware is working in main thread
DatabaseLogger.clear_commands
test_client = Familia.dbclient
test_client.set("setup_test", "value")
setup_commands = DatabaseLogger.commands.size

# Now run the actual test
DatabaseLogger.clear_commands
barrier = Concurrent::CyclicBarrier.new(50)
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

50.times do |i|
  threads << Thread.new do
    barrier.wait  # Synchronize start to maximize contention
    dbclient.set("thread_key_#{i}", "value_#{i}")
  end
end

threads.each(&:join)
commands = DatabaseLogger.commands

# All commands should be captured (no lost writes)
# No nil entries should exist in the commands array
# Note: setup_commands verifies middleware is working (should be 1)
[setup_commands, commands.size, commands.any?(nil), commands.all? { |cmd| cmd.respond_to?(:command) }]
#=> [1, 50, false, true]

## Pipelined commands are thread-safe under concurrent access from 25 threads
DatabaseLogger.clear_commands
barrier = Concurrent::CyclicBarrier.new(25)
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

25.times do |i|
  threads << Thread.new do
    barrier.wait
    dbclient.pipelined do |pipeline|
      pipeline.set("pipeline_thread_#{i}_key1", "val1")
      pipeline.set("pipeline_thread_#{i}_key2", "val2")
    end
  end
end

threads.each(&:join)
commands = DatabaseLogger.commands

# Each thread creates one pipeline command (25 total)
# Verify no nil entries and all are proper CommandMessage objects
[commands.size, commands.any?(nil), commands.all? { |cmd| cmd.respond_to?(:command) }]
#=> [25, false, true]

## Mixed middleware operations (call, call_pipelined, call_once) are thread-safe
DatabaseLogger.clear_commands
barrier = Concurrent::CyclicBarrier.new(60)
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

60.times do |i|
  threads << Thread.new do
    barrier.wait

    case i % 3
    when 0  # Regular call
      dbclient.set("mixed_#{i}", "val")
    when 1  # Pipelined
      dbclient.pipelined { |p| p.get("mixed_#{i}") }
    when 2  # Multiple rapid calls
      3.times { dbclient.get("mixed_#{i}") }
    end
  end
end

threads.each(&:join)
commands = DatabaseLogger.commands

# Verify no nil entries regardless of operation type
# All entries should be valid CommandMessage instances
[commands.any?(nil), commands.all? { |cmd| cmd.is_a?(DatabaseLogger::CommandMessage) }]
#=> [false, true]

## sample_rate counter is thread-safe with 100 concurrent operations
# REMOVED: This test had incorrect expectations. The sample_rate controls LOGGING
# output, not COMMAND CAPTURE. Per database_logger.rb:153-154:
# "Command capture is unaffected - only logger output is sampled."
# The commands array always contains all commands regardless of sample_rate.
# Thread safety of the AtomicFixnum counter is verified by other tests.

## Rapid sequential calls within threads don't corrupt shared state
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = nil  # Log everything
latch = Concurrent::CountDownLatch.new(20)
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

20.times do |i|
  threads << Thread.new do
    # Rapid-fire 10 operations per thread to test state isolation
    10.times do |j|
      dbclient.set("rapid_#{i}_#{j}", "val")
    end
    latch.count_down
  end
end

latch.wait(5)  # 5 second timeout
commands = DatabaseLogger.commands

# Should have 200 commands (20 threads × 10 calls)
# Most importantly: NO nil entries from rapid sequential access
[commands.size, commands.any?(nil)]
#=> [200, false]

## clear_commands doesn't cause nil entries during concurrent logging
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = nil
barrier = Concurrent::CyclicBarrier.new(51)  # 50 loggers + 1 clearer
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

# 50 threads logging continuously
50.times do |i|
  threads << Thread.new do
    barrier.wait
    10.times do |j|
      dbclient.set("clear_test_#{i}_#{j}", "val")
    end
  end
end

# 1 thread clearing repeatedly to create contention
clearer = Thread.new do
  barrier.wait
  5.times do
    sleep 0.001  # Small delay between clears
    DatabaseLogger.clear_commands
  end
end

threads.each(&:join)
clearer.join

# After clearing, commands should be empty or valid (never contain nil)
# This tests whether clear_commands can corrupt the array during active logging
commands = DatabaseLogger.commands
[commands.any?(nil)]
#=> [false]

## CommandMessage structure is preserved under concurrent access
DatabaseLogger.clear_commands
barrier = Concurrent::CyclicBarrier.new(30)
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

30.times do |i|
  threads << Thread.new do
    barrier.wait
    dbclient.set("structure_test_#{i}", "value_#{i}")
  end
end

threads.each(&:join)
commands = DatabaseLogger.commands

# Verify all CommandMessage fields are properly initialized
# This ensures the Data.define structure isn't corrupted by concurrency
all_valid = commands.all? do |cmd|
  cmd.command.is_a?(String) &&
  cmd.μs.is_a?(Integer) &&
  cmd.timeline.is_a?(Float)
end

[commands.size, commands.any?(nil), all_valid]
#=> [30, false, true]

## Concurrent pipelined operations with varying sizes don't cause corruption
# REMOVED: This test was checking exact pipeline command count which can vary
# due to intentionally non-atomic append_command trimming logic.
# See database_logger.rb:214-217 - we don't care about exact count when trimming.
# The important invariants (no nil entries, successful operations) are tested elsewhere.

## AtomicFixnum counter increments correctly under high contention
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = 1.0  # Track every increment but log everything
counter_start = DatabaseLogger.instance_variable_get(:@sample_counter).value

barrier = Concurrent::CyclicBarrier.new(100)
threads = []
dbclient = Familia.dbclient  # Get connection in main thread (has middleware)

100.times do |i|
  threads << Thread.new do
    barrier.wait
    dbclient.set("counter_test_#{i}", "val")
  end
end

threads.each(&:join)
counter_end = DatabaseLogger.instance_variable_get(:@sample_counter).value
commands = DatabaseLogger.commands

# Counter should have incremented by exactly 100
# Commands should have all 100 entries with no nil values
[counter_end - counter_start, commands.size, commands.any?(nil)]
#=> [100, 100, false]

# Teardown: Reset to defaults
DatabaseLogger.sample_rate = nil
DatabaseLogger.structured_logging = false
DatabaseLogger.clear_commands
