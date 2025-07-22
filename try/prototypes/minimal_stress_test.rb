# Minimal stress test to identify issues

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false
BankAccount.redis.flushdb

puts "Starting minimal stress test..."

# Test with just a few threads
threads = []
errors = []
successful_ops = 0

3.times do |i|
  threads << Thread.new(i) do |thread_id|
    begin
      account = BankAccount.new(balance: 1000, holder_name: "Thread#{thread_id}")
      account.save
      
      3.times do |op_num|
        begin
          Familia.atomic do
            account.refresh!
            current = account.balance
            account.balance = current + 10
            account.save
          end
          successful_ops += 1
          print "."
        rescue => e
          errors << { thread: thread_id, op: op_num, error: e.message, class: e.class }
          print "E"
        end
      end
    rescue => e
      errors << { thread: thread_id, setup_error: e.message, class: e.class }
      print "S"
    end
  end
end

threads.each(&:join)

puts "\nResults:"
puts "Successful operations: #{successful_ops}"
puts "Errors: #{errors.size}"

if errors.any?
  puts "\nError details:"
  errors.each do |error|
    puts "- #{error}"
  end
end