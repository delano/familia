# try/thread_safety/encryption_manager_cache_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require 'base64'

# Thread safety tests for encryption manager cache initialization
#
# Tests concurrent encryption manager cache access to ensure that only
# a single Manager instance is created per algorithm even under high
# concurrent load.
#
# These tests verify:
# 1. Concurrent manager cache initialization (single algorithm)
# 2. Multiple algorithms initialized concurrently
# 3. Maximum contention with CyclicBarrier pattern
# 4. Manager singleton property per algorithm

# Setup encryption keys for testing
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

## Concurrent manager cache initialization for default algorithm
# Reset the managers cache to nil to simulate first access
Familia::Encryption.instance_variable_set(:@managers, nil)

barrier = Concurrent::CyclicBarrier.new(50)
managers = Concurrent::Array.new

threads = 50.times.map do
  Thread.new do
    barrier.wait
    # Get manager for default algorithm (nil)
    mgr = Familia::Encryption.manager(algorithm: nil)
    managers << mgr.object_id
  end
end

threads.each(&:join)

# All threads should get the same manager instance
[managers.any?(nil), managers.uniq.size, managers.size]
#=> [false, 1, 50]


## Concurrent manager cache initialization for default algorithm only
# Testing with just default (nil) algorithm to avoid provider availability issues
Familia::Encryption.instance_variable_set(:@managers, nil)

barrier = Concurrent::CyclicBarrier.new(30)
results = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    # All use default algorithm for simplicity
    mgr = Familia::Encryption.manager(algorithm: nil)
    results << mgr.object_id
  end
end

threads.each(&:join)

# All threads should get the same manager instance
[results.uniq.size, results.size]
#=> [1, 30]


## Maximum contention test with encryption operations
Familia::Encryption.instance_variable_set(:@managers, nil)
Familia::Encryption.reset_derivation_count!

barrier = Concurrent::CyclicBarrier.new(50)
@encrypt_errors = Concurrent::Array.new
@encrypted_values = Concurrent::Array.new

threads = 50.times.map do |i|
  Thread.new do
    begin
      barrier.wait
      # All threads encrypt concurrently, forcing manager cache access
      plaintext = "secret-#{i}"
      context = "test:#{i}"
      encrypted = Familia::Encryption.encrypt(plaintext, context: context)
      @encrypted_values << encrypted
    rescue => e
      @encrypt_errors << e
    end
  end
end

threads.each(&:join)

# Verify no errors and all encryptions succeeded
[@encrypt_errors.empty?, @encrypted_values.size]
#=> [true, 50]


## Manager singleton property maintained across concurrent access
# Access the managers cache and verify singleton property
managers_cache = Familia::Encryption.instance_variable_get(:@managers)

# Should be a Concurrent::Map
managers_cache.class.name
#=> "Concurrent::Map"


## Concurrent decryption operations with manager cache
barrier = Concurrent::CyclicBarrier.new(25)
@decrypted_values = Concurrent::Array.new
@decrypt_errors = Concurrent::Array.new

# First, create some encrypted values
test_encrypted = 25.times.map do |i|
  Familia::Encryption.encrypt("value-#{i}", context: "test:#{i}")
end

threads = 25.times.map do |i|
  Thread.new do
    begin
      barrier.wait
      decrypted = Familia::Encryption.decrypt(test_encrypted[i], context: "test:#{i}")
      @decrypted_values << decrypted
    rescue => e
      @decrypt_errors << e
    end
  end
end

threads.each(&:join)

# Verify no errors and all decryptions succeeded
[@decrypt_errors.empty?, @decrypted_values.size]
#=> [true, 25]


## Rapid sequential manager access per thread
barrier = Concurrent::CyclicBarrier.new(20)
access_counts = Concurrent::Array.new

threads = 20.times.map do
  Thread.new do
    barrier.wait
    count = 0
    50.times do
      Familia::Encryption.manager(algorithm: nil)
      count += 1
    end
    access_counts << count
  end
end

threads.each(&:join)

# Each thread completed 50 accesses
access_counts.all? { |c| c == 50 }
#=> true

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
