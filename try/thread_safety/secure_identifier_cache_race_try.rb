# try/thread_safety/secure_identifier_cache_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for SecureIdentifier min_length cache initialization
#
# Tests concurrent SecureIdentifier cache access to ensure atomic cache
# population and consistent calculations across all concurrent ID generation
# requests.
#
# These tests verify:
# 1. Concurrent cache initialization for same [bits, base] key
# 2. Multiple cache keys accessed concurrently
# 3. Maximum contention with CyclicBarrier pattern
# 4. Cache value consistency and correctness

## Concurrent cache initialization for same [bits, base] key
# Reset the cache to nil to simulate first access
Familia::SecureIdentifier.instance_variable_set(:@min_length_for_bits_cache, nil)

barrier = Concurrent::CyclicBarrier.new(50)
cache_values = Concurrent::Array.new

threads = 50.times.map do
  Thread.new do
    barrier.wait
    # All threads request same [bits, base] combination
    length = Familia::SecureIdentifier.min_length_for_bits(128, 36)
    cache_values << length
  end
end

threads.each(&:join)

# All threads should get the same value
[cache_values.uniq.size, cache_values.size, cache_values.first]
#=> [1, 50, 25]


## Concurrent cache initialization for multiple [bits, base] combinations
Familia::SecureIdentifier.instance_variable_set(:@min_length_for_bits_cache, nil)

barrier = Concurrent::CyclicBarrier.new(30)
results = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    # Different combinations of bits and base
    bits = [64, 128, 256][i % 3]
    base = [16, 36, 62][i / 10]

    length = Familia::SecureIdentifier.min_length_for_bits(bits, base)
    results << [bits, base, length]
  end
end

threads.each(&:join)

# All operations completed successfully
results.size
#=> 30


## Maximum contention test with ID generation
Familia::SecureIdentifier.instance_variable_set(:@min_length_for_bits_cache, nil)

barrier = Concurrent::CyclicBarrier.new(50)
@id_gen_errors = Concurrent::Array.new
@generated_ids = Concurrent::Array.new

threads = 50.times.map do |i|
  Thread.new do
    begin
      barrier.wait
      # Generate IDs which internally calls min_length_for_bits
      id = Familia.generate_id(36)
      @generated_ids << id
    rescue => e
      @id_gen_errors << e
    end
  end
end

threads.each(&:join)

# Verify no errors and all IDs generated
[@id_gen_errors.empty?, @generated_ids.size]
#=> [true, 50]


## Verify cache is Concurrent::Map (if it was initialized)
cache = Familia::SecureIdentifier.instance_variable_get(:@min_length_for_bits_cache)
cache.nil? || cache.class.name == "Concurrent::Map"
#=> true


## Concurrent lite ID generation
Familia::SecureIdentifier.instance_variable_set(:@min_length_for_bits_cache, nil)

barrier = Concurrent::CyclicBarrier.new(30)
@lite_ids = Concurrent::Array.new
@lite_errors = Concurrent::Array.new

threads = 30.times.map do
  Thread.new do
    begin
      barrier.wait
      id = Familia.generate_lite_id(36)
      @lite_ids << id
    rescue => e
      @lite_errors << e
    end
  end
end

threads.each(&:join)

# No errors and all IDs generated
[@lite_errors.empty?, @lite_ids.size]
#=> [true, 30]


## Concurrent trace ID generation
barrier = Concurrent::CyclicBarrier.new(25)
@trace_ids = Concurrent::Array.new
@trace_errors = Concurrent::Array.new

threads = 25.times.map do
  Thread.new do
    begin
      barrier.wait
      id = Familia.generate_trace_id(36)
      @trace_ids << id
    rescue => e
      @trace_errors << e
    end
  end
end

threads.each(&:join)

# No errors and all IDs generated
[@trace_errors.empty?, @trace_ids.size]
#=> [true, 25]


## Verify hex fast-path doesn't use cache (base 16)
# This verifies the hex optimization path still works correctly
barrier = Concurrent::CyclicBarrier.new(20)
hex_lengths = Concurrent::Array.new

threads = 20.times.map do
  Thread.new do
    barrier.wait
    # Base 16 uses fast-path, should not hit cache
    length = Familia::SecureIdentifier.min_length_for_bits(256, 16)
    hex_lengths << length
  end
end

threads.each(&:join)

# All should get the same value (64 for 256-bit hex)
[hex_lengths.uniq.size, hex_lengths.first]
#=> [1, 64]


## Rapid sequential cache access per thread
barrier = Concurrent::CyclicBarrier.new(20)
access_counts = Concurrent::Array.new

threads = 20.times.map do
  Thread.new do
    barrier.wait
    count = 0
    100.times do
      Familia::SecureIdentifier.min_length_for_bits(128, 36)
      count += 1
    end
    access_counts << count
  end
end

threads.each(&:join)

# Each thread completed 100 accesses
access_counts.all? { |c| c == 100 }
#=> true


## Cache correctness under concurrent load
# Reset cache and verify correct calculations for various combinations
Familia::SecureIdentifier.instance_variable_set(:@min_length_for_bits_cache, nil)

barrier = Concurrent::CyclicBarrier.new(15)
correctness_results = Concurrent::Array.new

# Known correct values for verification
expected_values = {
  [64, 36] => 13,
  [128, 36] => 25,
  [256, 36] => 50,
  [64, 62] => 11,
  [128, 62] => 22,
}

threads = 15.times.map do |i|
  Thread.new do
    barrier.wait
    # Each thread calculates multiple values
    expected_values.each do |key, expected|
      bits, base = key
      result = Familia::SecureIdentifier.min_length_for_bits(bits, base)
      correctness_results << (result == expected)
    end
  end
end

threads.each(&:join)

# All calculations should be correct
correctness_results.all?
#=> true
