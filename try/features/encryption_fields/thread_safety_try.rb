# try/features/encryption_fields/thread_safety_try.rb

require 'concurrent'
require 'base64'

require_relative '../../helpers/test_helpers'

# Setup encryption keys for testing
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class ThreadTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

# Thread-safe debug logging helper
@debug_mutex = Mutex.new
def debug(msg)
  return unless ENV['FAMILIA_DEBUG']
  @debug_mutex.synchronize { puts "DEBUG: #{msg}" }
end

## Concurrent encryption operations maintain counter integrity
Familia::Encryption.reset_derivation_count!
@results = Concurrent::Array.new
@errors = Concurrent::Array.new

debug "Starting 10 threads for concurrent operations..."

@threads = 10.times.map do |i|
  Thread.new do
    begin
      model = ThreadTest.new(id: "thread-#{i}")
      5.times do |j|
        model.secret = "secret-#{i}-#{j}"  # encrypt (derivation)
        retrieved = model.secret           # decrypt (derivation)
        @results << retrieved
      end
      debug "Thread #{i} completed successfully"
    rescue => e
      debug "Thread #{i} failed: #{e.class}: #{e.message}"
      @errors << e
    end
  end
end

@threads.each(&:join)

debug "All threads joined. Results: #{@results.size}, Errors: #{@errors.size}"
debug "Derivation count: #{Familia::Encryption.derivation_count.value}"

if @errors.any?
  debug "Error details:"
  @errors.each_with_index { |e, i| debug "  #{i+1}. #{e.class}: #{e.message}" }
end

@errors.empty?
#=> true

## All expected results collected (10 threads × 5 operations = 50 results)
@results.size
#=> 50

## Each thread did 5 write + 5 read = 10 derivations
# Total: 10 threads * 10 derivations = 100
Familia::Encryption.derivation_count.value
#=> 100

## Key rotation operations work safely under concurrent access
debug "Starting key rotation test with 4 threads..."

@rotation_errors = Concurrent::Array.new
@rotation_results = Concurrent::Array.new

@rotation_threads = 4.times.map do |i|
  Thread.new do
    begin
      # Each thread alternates between v1 and v2
      thread_version = i.even? ? :v1 : :v2

      10.times do |j|
        debug "Thread #{i}, iteration #{j}, using version #{thread_version}"

        # Temporarily switch key version for this operation
        original_version = Familia.config.current_key_version
        Familia.config.current_key_version = thread_version

        begin
          model = ThreadTest.new(id: "race-#{i}-#{j}")
          model.secret = "test-#{i}-#{j}"   # encrypt
          retrieved = model.secret          # decrypt
          @rotation_results << retrieved
          debug "Thread #{i}, iteration #{j} completed"
        ensure
          # Restore original version
          Familia.config.current_key_version = original_version
        end
      end
    rescue => e
      debug "Rotation thread #{i} failed: #{e.class}: #{e.message}"
      @rotation_errors << e
    end
  end
end

@rotation_threads.each(&:join)

debug "Key rotation test completed. Results: #{@rotation_results.size}, Errors: #{@rotation_errors.size}"

if @rotation_errors.any?
  debug "Rotation error details:"
  @rotation_errors.each_with_index { |e, i| debug "  #{i+1}. #{e.class}: #{e.message}" }
end

@rotation_errors.empty?
#=> true

## All rotation operations completed successfully (4 threads × 10 operations = 40 results)
@rotation_results.size
#=> 40

## Atomic counter maintains accuracy under maximum contention
debug "Starting atomic counter test with 20 threads..."
debug "Count before reset: #{Familia::Encryption.derivation_count.value}"

Familia::Encryption.reset_derivation_count!
sleep(0.01) # Minimal delay to ensure reset takes effect

debug "Count after reset: #{Familia::Encryption.derivation_count.value}"

barrier = Concurrent::CyclicBarrier.new(20)
@counter_errors = Concurrent::Array.new

counter_threads = 20.times.map do |i|
  Thread.new do
    begin
      barrier.wait # Synchronize start for maximum contention
      model = ThreadTest.new(id: "counter-test-#{i}")
      model.secret = 'test'  # Single encrypt operation (1 derivation)
      debug "Counter thread #{i} completed"
    rescue => e
      debug "Counter thread #{i} failed: #{e.class}: #{e.message}"
      @counter_errors << e
    end
  end
end

counter_threads.each(&:join)

debug "Atomic counter test completed. Final count: #{Familia::Encryption.derivation_count.value}"

@counter_errors.empty?
#=> true

## Exactly 20 derivations, no lost increments
Familia::Encryption.derivation_count.value
#=> 20

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
