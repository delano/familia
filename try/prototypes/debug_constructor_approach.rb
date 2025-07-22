# Test different constructor approaches

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false
BankAccount.redis.flushdb

puts "Testing different constructor approaches..."

# Approach 1: Create empty, then assign
puts "\nApproach 1: Create empty, then assign"
begin
  account1 = BankAccount.new
  account1.balance = 1000
  account1.holder_name = "Test1"
  puts "✅ Fields set: balance=#{account1.balance}, holder_name=#{account1.holder_name}"
  puts "✅ Save result: #{account1.save}"
rescue => e
  puts "❌ Error: #{e.message}"
end

# Approach 2: Use keyword args in new
puts "\nApproach 2: Use keyword args in new (direct)"
begin
  account2 = BankAccount.new(balance: 2000, holder_name: "Test2")
  puts "✅ Created with kwargs: balance=#{account2.balance}, holder_name=#{account2.holder_name}"
  puts "✅ Save result: #{account2.save}"
rescue => e
  puts "❌ Error: #{e.message}"
end

# Approach 3: Look at what Familia::Horreum expects
puts "\nApproach 3: Familia::Horreum constructor signature"
puts "Horreum.initialize signature: #{Familia::Horreum.instance_method(:initialize).parameters}"

# Approach 4: Fix StressTestAccount by not overriding initialize
puts "\nApproach 4: Minimal StressTestAccount"
class MinimalStressTestAccount < BankAccount
  # Don't override initialize at all
end

begin
  account3 = MinimalStressTestAccount.new
  account3.balance = 3000
  account3.holder_name = "Test3"
  puts "✅ MinimalStressTestAccount created: balance=#{account3.balance}, holder_name=#{account3.holder_name}"
  puts "✅ Save result: #{account3.save}"
rescue => e
  puts "❌ Error: #{e.message}"
end