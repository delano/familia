# Debug BankAccount initialization process

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v3_connection_pool_helpers'

Familia.debug = false

puts "Debugging BankAccount initialization..."

# Check what methods BankAccount has
puts "\nBankAccount methods:"
puts "- initialize method: #{BankAccount.instance_methods(false).include?(:initialize)}"
puts "- init method: #{BankAccount.instance_methods(false).include?(:init)}"

# Check superclass methods
puts "\nFamilia::Horreum methods:"
horreum_methods = Familia::Horreum.instance_methods(false)
puts "- initialize: #{horreum_methods.include?(:initialize)}"
puts "- init: #{horreum_methods.include?(:init)}"

puts "\nTesting BankAccount creation with debugging..."

# Monkey patch BankAccount to see what's happening
class BankAccount
  alias_method :original_initialize, :initialize
  
  def initialize(*args, **kwargs)
    puts "BankAccount.initialize called with args: #{args.inspect}, kwargs: #{kwargs.inspect}"
    result = original_initialize(*args, **kwargs)
    puts "After original initialize:"
    puts "  @balance: #{@balance.inspect}"
    puts "  @holder_name: #{@holder_name.inspect}"
    puts "  @account_number: #{@account_number.inspect}"
    result
  end
end

begin
  account = BankAccount.new(balance: 1000, holder_name: "Debug")
  puts "\nFinal state:"
  puts "  balance: #{account.balance}"
  puts "  holder_name: #{account.holder_name}"
  puts "  account_number: #{account.account_number}"
rescue => e
  puts "Error: #{e.message}"
end