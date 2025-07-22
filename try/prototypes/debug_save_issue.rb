# Debug the save issue with StressTestAccount

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false
BankAccount.redis.flushdb

# Test the exact StressTestAccount implementation from the stress test
class DebugStressTestAccount < BankAccount
  def initialize(**kwargs)
    puts "DebugStressTestAccount.initialize with: #{kwargs.inspect}"
    super(**kwargs)
    puts "After super: balance=#{@balance}, holder_name=#{@holder_name}, account_number=#{@account_number}"
    
    # Ensure the init method is called to set account_number
    if respond_to?(:init)
      puts "Calling init method..."
      init 
      puts "After init: account_number=#{@account_number}"
    else
      puts "No init method available"
    end
    
    puts "Final state: balance=#{balance}, holder_name=#{holder_name}, account_number=#{account_number}"
  end
  
  def save(using: nil)
    puts "DebugStressTestAccount.save called with using: #{using}"
    puts "Current state before save: balance=#{balance}, holder_name=#{holder_name}, account_number=#{account_number}"
    
    # Call the parent save method
    super(using: using)
  end
end

puts "Creating DebugStressTestAccount..."
begin
  account = DebugStressTestAccount.new(balance: 1000, holder_name: "DebugTest")
  puts "\n✅ Account created successfully"
  
  puts "\nTrying to save..."
  result = account.save
  puts "✅ Save successful: #{result}"
  
rescue => e
  puts "\n❌ Error: #{e.message} (#{e.class})"
  puts "Backtrace:"
  puts e.backtrace.first(5)
end