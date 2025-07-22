# Debug the identifier issue

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = true
BankAccount.redis.flushdb

puts "Debugging identifier issue..."

# Create working BankAccount
puts "\nCreating working BankAccount..."
working_account = BankAccount.new(balance: 1000, holder_name: "Working")
puts "Working account - account_number: #{working_account.account_number}"
puts "Working account - identifier result: #{working_account.identifier}"

# Create failing subclass
class FailingAccount < BankAccount
end

puts "\nCreating failing FailingAccount..."
failing_account = FailingAccount.new
failing_account.balance = 1000
failing_account.holder_name = "Failing"
puts "Failing account - account_number: #{failing_account.account_number}"

begin
  puts "Failing account - identifier result: #{failing_account.identifier}"
rescue => e
  puts "Identifier method failed: #{e.message}"
end

# Let's see what the identifier method expects
puts "\nBankAccount identifier definition: #{BankAccount.identifier_definition rescue 'method not available'}"

# Let's manually check what Horreum uses for identifier
puts "\nChecking BankAccount class structure:"
puts "- Fields: #{BankAccount.fields rescue 'no fields method'}"
puts "- Identifier: #{BankAccount.identifier_definition rescue 'no identifier_definition method'}"

# Let's try to understand what's nil
puts "\nDebugging the failing account state:"
puts "Instance variables: #{failing_account.instance_variables}"
failing_account.instance_variables.each do |var|
  puts "  #{var}: #{failing_account.instance_variable_get(var).inspect}"
end