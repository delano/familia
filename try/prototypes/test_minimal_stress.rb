# Test minimal stress test to identify the exact issue

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false
BankAccount.redis.flushdb

class SimpleStressTestAccount < BankAccount
  # Exact same as the stress test but without any constructor override
end

puts "Testing SimpleStressTestAccount directly..."

# Test 1: Can we create and save a SimpleStressTestAccount?
begin
  account = SimpleStressTestAccount.new
  account.balance = 1000
  account.holder_name = "Direct Test"
  puts "✅ Created account: #{account.account_number}"
  
  result = account.save
  puts "✅ Save successful: #{result}"
rescue => e
  puts "❌ Direct test failed: #{e.message} (#{e.class})"
  puts "Backtrace: #{e.backtrace.first(3)}"
end

# Test 2: Can we do it in a thread?
puts "\nTesting in a single thread..."
success = false
error = nil

thread = Thread.new do
  begin
    account = SimpleStressTestAccount.new
    account.balance = 2000
    account.holder_name = "Thread Test"
    account.save
    success = true
  rescue => e
    error = e
  end
end

thread.join

if success
  puts "✅ Single thread test successful"
else
  puts "❌ Single thread test failed: #{error.message} (#{error.class})"
end

# Test 3: Can we do it with the connection pool setup?
puts "\nTesting with connection pool setup..."

# Mimic the stress test connection pool setup
pool_size = 10
pool_timeout = 5

Familia.class_eval do
  @@connection_pool = ConnectionPool.new(
    size: pool_size,
    timeout: pool_timeout
  ) do
    Redis.new(url: Familia.uri.to_s)
  end
end

thread2 = Thread.new do
  begin
    account = SimpleStressTestAccount.new
    account.balance = 3000
    account.holder_name = "Pool Test"
    account.save
    puts "✅ Connection pool thread successful"
  rescue => e
    puts "❌ Connection pool thread failed: #{e.message} (#{e.class})"
  end
end

thread2.join

puts "\nAll tests completed."