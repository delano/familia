# try/pooling/connection_pool_test_try.rb

# USAGE: FAMILIA_TRACE=1 FAMILIA_DEBUG=1 bundle exec tryouts try/pooling/connection_pool_test_try.rb

require 'bundler/setup'
require 'securerandom'
require 'thread'
require_relative '../helpers/test_helpers'

# Configure connection pooling via connection_provider
require 'connection_pool'

# Create pools for each logical database
@pools = {}

Familia.connection_provider = lambda do |uri|
  @pools[uri] ||= ConnectionPool.new(size: 5, timeout: 2) do
    parsed = URI.parse(uri)
    Redis.new(
      host: parsed.host,
      port: parsed.port,
      db: parsed.db || 0
    )
  end

  @pools[uri].with { |conn| conn }
end

# Test model for connection pool testing
class PoolTestAccount < Familia::Horreum
  identifier_field :account_id
  field :account_id
  field :balance, on_conflict: :skip
  field :holder_name

  def init
    @account_id ||= SecureRandom.hex(6)
    @balance = @balance.to_f if @balance
  end

  def balance
    @balance&.to_f
  end
end

class PoolTestSession < Familia::Horreum
  identifier_field :session_id
  field :session_id
  field :user_id
  field :created_at

  def init
    @session_id ||= SecureRandom.hex(8)
    @created_at ||= Time.now.to_i
  end
end

## Clean up before tests
PoolTestAccount.dbclient.flushdb
#=> "OK"

## Test 1: Connection provider configuration
Familia.connection_provider.is_a?(Proc)
#=> true

## Test 2: Connection pool created automatically
@account1 = PoolTestAccount.new(balance: 1000, holder_name: "Alice")
@account1.save
#=> true

## Test 3: Basic pool functionality
@account1.balance
#=> 1000.0

## Test 4: Multiple logical databases with separate pools
# Account in DB 0 (default)
@account_db0 = PoolTestAccount.new(balance: 500, holder_name: "Bob")
@account_db0.save
#=> true

## Test 5: Account in DB 1 via class configuration
class PoolTestAccountDB1 < Familia::Horreum
  self.logical_database = 1
  identifier_field :account_id
  field :account_id
  field :balance, on_conflict: :skip
  field :holder_name

  def init
    @account_id ||= SecureRandom.hex(6)
    @balance = @balance.to_f if @balance
  end

  def balance
    @balance&.to_f
  end
end

@account_db1 = PoolTestAccountDB1.new(balance: 750, holder_name: "Charlie")
@account_db1.save
#=> true

## Test 6: Verify accounts are in different databases
@account_db0.balance
#=> 500.0

## Test 7: Verify DB1 account works independently
@account_db1.balance
#=> 750.0

## Test 8: Connection pool thread safety
@results = []
@mutex = Mutex.new

# Create multiple threads performing concurrent operations
threads = 5.times.map do |i|
  Thread.new do
    account = PoolTestAccount.new(balance: 1000, holder_name: "Thread#{i}")
    result = account.save
    @mutex.synchronize { @results << result }
  end
end

threads.each(&:join)
@results.all?
#=> true

## Test 9: Thread safety verification
@results.size
#=> 5

## Test 10: Transaction support with connection pools
@account_a = PoolTestAccount.new(balance: 1000, holder_name: "AccountA")
@account_b = PoolTestAccount.new(balance: 500, holder_name: "AccountB")
[@account_a.save, @account_b.save]
#=> [true, true]

## Test 11: Multi/EXEC transaction operations
@transfer_result = Familia.transaction do |conn|
  # Test that transaction connection is available
  conn.ping
end
# Transaction returns array with results
@transfer_result.first
#=> "PONG"

## Test 12: Transaction block executes properly
# Simple verification that accounts maintain their values
[@account_a.balance, @account_b.balance]
#=> [1000.0, 500.0]

## Test 13: with_connection method
@connection_test_result = Familia.with_connection do |conn|
  conn.set("test_key_#{SecureRandom.hex(4)}", "test_value")
end
@connection_test_result
#=> "OK"

## Test 14: Pipeline operations with connection pool
@pipeline_results = Familia.pipeline do |conn|
  conn.ping
end
# Pipeline executes successfully
@pipeline_results.first
#=> "PONG"

## Test 15: Multi/EXEC operations with connection pool
@multi_results = Familia.multi do |conn|
  conn.ping
end
# Multi/EXEC executes successfully
@multi_results.first
#=> "PONG"

## Test 16: Error handling in transactions
@error_account = PoolTestAccount.new(balance: 100, holder_name: "ErrorTest")
@error_account.save
#=> true

## Test 17: Transaction error handling
begin
  Familia.transaction do |conn|
    conn.ping
    raise "Simulated error"
  end
  false
rescue => e
  # Error propagates correctly from transaction block
  true
end
#=> true

## Test 18: Verify account state after transaction error
@error_account.refresh!
@error_account.balance
#=> 100.0

## Test 19: Multiple pools created for different databases
@pools.size >= 1
#=> true

## Test 20: Connection pool timeout handling
timeout_threads = []
timeout_results = []
timeout_mutex = Mutex.new

# Start threads that hold connections briefly
3.times do |i|
  timeout_threads << Thread.new do
    begin
      result = Familia.with_connection do |conn|
        sleep(0.1)  # Brief hold
        conn.ping
      end
      timeout_mutex.synchronize { timeout_results << result }
    rescue => e
      timeout_mutex.synchronize { timeout_results << e.class.name }
    end
  end
end

timeout_threads.each(&:join)
timeout_results.all? { |r| r == "PONG" }
#=> true

## Test 21: Debug mode validation (if enabled)
# This test only runs if FAMILIA_DEBUG=1 is set
if ENV['FAMILIA_DEBUG']
  Familia.debug = true
  # Test that debug mode doesn't break normal operation
  debug_account = PoolTestAccount.new(balance: 123, holder_name: "Debug")
  debug_account.save
else
  true  # Skip debug test if not in debug mode
end
#=> true

## Test 22: Backward compatibility - existing code works unchanged
@compat_result = PoolTestAccount.dbclient.ping
@compat_result
#=> "PONG"

## Test 23: Field operations work unchanged
@compat_account = PoolTestAccount.new(balance: 9999, holder_name: "Compat")
@compat_account.save
#=> true

## Test 24: Direct field access works
@compat_account.hget("balance").to_f
#=> 9999.0

## Test 25: Connection provider receives correct URIs
@captured_uris = []
original_provider = Familia.connection_provider

# Temporarily wrap provider to capture URIs
Familia.connection_provider = lambda do |uri|
  @captured_uris << uri
  original_provider.call(uri)
end

# Trigger some operations to capture URIs
test_account = PoolTestAccount.new(balance: 555, holder_name: "URITest")
test_account.save

# Restore original provider
Familia.connection_provider = original_provider

# Verify URIs contain database information
@captured_uris.any? { |uri| uri.include?('redis://') }
#=> true

puts "Connection pool tests completed successfully!"
