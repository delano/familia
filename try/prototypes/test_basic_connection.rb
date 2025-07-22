# Quick test to verify basic connection pool functionality

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

puts "Testing basic connection pool setup..."

# Test 1: Basic connection
begin
  Familia.connect
  puts "✅ Familia connected successfully"
rescue => e
  puts "❌ Familia connection failed: #{e.message}"
  exit 1
end

# Test 2: Clean database
begin
  BankAccount.redis.flushdb
  puts "✅ Database cleaned successfully"
rescue => e
  puts "❌ Database clean failed: #{e.message}"
  exit 1
end

# Test 3: Create and save account
begin
  account = BankAccount.new(balance: 1000, holder_name: "Test")
  result = account.save
  puts "✅ Account saved: #{result}"
rescue => e
  puts "❌ Account save failed: #{e.message}"
  puts "Error class: #{e.class}"
  puts "Backtrace: #{e.backtrace.first(3).join('\n')}"
  exit 1
end

# Test 4: Connection pool
begin
  pool = Familia.connection_pool
  puts "✅ Connection pool available: size=#{pool.size rescue 'unknown'}"
rescue => e
  puts "❌ Connection pool access failed: #{e.message}"
end

# Test 5: Atomic operation
begin
  result = Familia.atomic do
    account.balance = 500
    account.save
  end
  puts "✅ Atomic operation completed: #{result.class}"
rescue => e
  puts "❌ Atomic operation failed: #{e.message}"
  puts "Error class: #{e.class}"
  puts "Backtrace: #{e.backtrace.first(3).join('\n')}"
end

puts "\nBasic tests completed!"