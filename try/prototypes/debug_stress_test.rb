# Debug version of stress test to identify issues

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false

# Clean database
BankAccount.redis.flushdb

puts "Creating test account..."
begin
  account = BankAccount.new(balance: 1000, holder_name: "DebugTest")
  puts "Account created: #{account.inspect}"
  
  result = account.save
  puts "Save result: #{result}"
  
  # Test complex operation
  puts "Testing complex operation..."
  account.refresh!
  current = account.balance
  puts "Current balance: #{current}"
  
  account.balance = current + 50
  result2 = account.save
  puts "Second save result: #{result2}"
  
rescue => e
  puts "Error: #{e.message}"
  puts "Error class: #{e.class}"
  puts "Backtrace:"
  puts e.backtrace.first(10)
end

puts "\nTesting atomic operation..."
begin
  result = Familia.atomic do
    account.balance = account.balance + 100
    account.save
  end
  puts "Atomic result: #{result}"
rescue => e
  puts "Atomic error: #{e.message}"
  puts "Error class: #{e.class}"
  puts "Backtrace:"
  puts e.backtrace.first(10)
end

puts "\nTesting thread safety..."
threads = []
2.times do |i|
  threads << Thread.new(i) do |thread_id|
    puts "Thread #{thread_id} starting..."
    begin
      local_account = BankAccount.new(balance: 500, holder_name: "Thread#{thread_id}")
      local_account.save
      puts "Thread #{thread_id} account saved"
      
      Familia.atomic do
        local_account.balance += 10
        local_account.save
      end
      puts "Thread #{thread_id} completed atomic operation"
    rescue => e
      puts "Thread #{thread_id} error: #{e.message} (#{e.class})"
    end
  end
end

threads.each(&:join)
puts "All threads completed"