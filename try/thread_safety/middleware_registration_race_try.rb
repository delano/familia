# try/thread_safety/middleware_registration_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for middleware registration
#
# Tests concurrent middleware registration to ensure that race conditions
# in the check-then-act pattern don't result in duplicate middleware
# registration or corrupted middleware chains.
#
# These tests verify:
# 1. Concurrent reconnect with middleware enabled
# 2. Concurrent middleware version increment atomicity
# 3. Middleware state consistency under concurrent access

@original_logger_flag = nil
@original_counter_flag = nil
@original_middleware_registered = nil
@original_logger_enabled = nil
@original_counter_enabled = nil

# Setup: Store original middleware state
@original_logger_flag = Familia.instance_variable_get(:@logger_registered)
@original_counter_flag = Familia.instance_variable_get(:@counter_registered)
@original_middleware_registered = Familia.instance_variable_get(:@middleware_registered)
@original_logger_enabled = Familia.enable_database_logging
@original_counter_enabled = Familia.enable_database_counter

## Concurrent reconnect calls with middleware enabled
Familia.enable_database_logging = true
Familia.enable_database_counter = true
barrier = Concurrent::CyclicBarrier.new(20)
results = Concurrent::Array.new

threads = 20.times.map do
  Thread.new do
    barrier.wait
    Familia.reconnect!
    results << Familia.instance_variable_get(:@middleware_registered)
  end
end

threads.each(&:join)
results.size
#=> 20

## Concurrent middleware version increments preserve all updates
initial_version = Familia.middleware_version
barrier = Concurrent::CyclicBarrier.new(100)

threads = 100.times.map do
  Thread.new do
    barrier.wait
    Familia.increment_middleware_version!
  end
end

threads.each(&:join)
Familia.middleware_version - initial_version
#=> 100

## Concurrent reconnect and version check
Familia.enable_database_logging = true
barrier = Concurrent::CyclicBarrier.new(15)
versions = Concurrent::Array.new

threads = 15.times.map do |i|
  Thread.new do
    barrier.wait
    if i < 5
      Familia.reconnect!
    end
    versions << Familia.middleware_version
  end
end

threads.each(&:join)
versions.size
#=> 15

## Concurrent middleware state reads during reconnects
barrier = Concurrent::CyclicBarrier.new(30)
state_reads = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    if i < 10
      Familia.reconnect!
    end
    state_reads << [
      Familia.instance_variable_get(:@logger_registered),
      Familia.instance_variable_get(:@counter_registered)
    ]
  end
end

threads.each(&:join)
state_reads.size
#=> 30

## Rapid sequential reconnects from multiple threads
barrier = Concurrent::CyclicBarrier.new(10)
reconnect_counts = Concurrent::Array.new

threads = 10.times.map do
  Thread.new do
    barrier.wait
    count = 0
    10.times do
      Familia.reconnect!
      count += 1
    end
    reconnect_counts << count
  end
end

threads.each(&:join)
reconnect_counts.all? { |c| c == 10 }
#=> true

## Concurrent middleware enable/disable during reconnect
Familia.enable_database_logging = false
Familia.enable_database_counter = false
barrier = Concurrent::CyclicBarrier.new(25)
enable_results = Concurrent::Array.new

threads = 25.times.map do |i|
  Thread.new do
    barrier.wait
    case i % 3
    when 0
      Familia.enable_database_logging = true
    when 1
      Familia.enable_database_counter = true
    when 2
      Familia.reconnect!
    end
    enable_results << :completed
  end
end

threads.each(&:join)
enable_results.size
#=> 25

# Teardown: Restore original middleware state
Familia.instance_variable_set(:@logger_registered, @original_logger_flag)
Familia.instance_variable_set(:@counter_registered, @original_counter_flag)
Familia.instance_variable_set(:@middleware_registered, @original_middleware_registered)
Familia.enable_database_logging = @original_logger_enabled
Familia.enable_database_counter = @original_counter_enabled
