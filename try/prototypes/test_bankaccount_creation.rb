# Test different ways to create BankAccount

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false
BankAccount.redis.flushdb

puts "Testing different ways to create BankAccount..."

# Test 1: Keyword arguments
puts "\nTest 1: Keyword arguments"
begin
  account1 = BankAccount.new(balance: 1000, holder_name: "Test1")
  puts "✅ Created with keywords: #{account1.account_number}"
  puts "   Balance: #{account1.balance}"
  puts "   Holder: #{account1.holder_name}"
  puts "   Save result: #{account1.save}"
rescue => e
  puts "❌ Keyword creation failed: #{e.message} (#{e.class})"
end

# Test 2: No arguments, then set fields
puts "\nTest 2: No args, then set fields"
begin
  account2 = BankAccount.new
  account2.balance = 500
  account2.holder_name = "Test2"
  puts "✅ Created empty then set: #{account2.account_number}"
  puts "   Balance: #{account2.balance}"
  puts "   Holder: #{account2.holder_name}"
  puts "   Save result: #{account2.save}"
rescue => e
  puts "❌ Empty creation failed: #{e.message} (#{e.class})"
end

# Test 3: Check what happens with StressTestAccount
puts "\nTest 3: StressTestAccount"

# Define StressTestAccount locally to test
class LocalStressTestAccount < BankAccount
  def initialize(**kwargs)
    puts "Initializing with kwargs: #{kwargs.inspect}"
    super(**kwargs)
    puts "After super, account_number: #{@account_number}"
    init if respond_to?(:init)
    puts "After init, account_number: #{@account_number}"
  end
end

begin
  account3 = LocalStressTestAccount.new(balance: 750, holder_name: "Test3")
  puts "✅ LocalStressTestAccount created: #{account3.account_number}"
  puts "   Balance: #{account3.balance}"
  puts "   Holder: #{account3.holder_name}"
  puts "   Save result: #{account3.save}"
rescue => e
  puts "❌ LocalStressTestAccount creation failed: #{e.message} (#{e.class})"
  puts "   Backtrace: #{e.backtrace.first(3)}"
end