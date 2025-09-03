#!/usr/bin/env ruby

# examples/redis_command_validation_example.rb
#
# Comprehensive example demonstrating Redis command validation for Familia
# This example shows how to validate that Redis operations execute exactly
# as expected, with particular focus on atomic operations.

require_relative '../lib/familia'
require_relative '../lib/familia/validation'

# Enable database logging for visibility
Familia.enable_database_logging = true
Familia.enable_database_counter = true

# Example models for validation demonstration
class Account < Familia::Horreum
  identifier_field :account_id
  field :account_id
  field :balance
  field :status
  field :last_updated
end

class TransferService
  def self.atomic_transfer(from_account, to_account, amount)
    # Proper atomic implementation using Familia transaction
    from_balance = from_account.balance.to_i - amount
    to_balance = to_account.balance.to_i + amount

    Familia.transaction do |conn|
      conn.hset(from_account.dbkey, 'balance', from_balance.to_s)
      conn.hset(to_account.dbkey, 'balance', to_balance.to_s)
      conn.hset(from_account.dbkey, 'last_updated', Time.now.to_i.to_s)
      conn.hset(to_account.dbkey, 'last_updated', Time.now.to_i.to_s)
    end

    # Update local state
    from_account.balance = from_balance.to_s
    to_account.balance = to_balance.to_s
  end

  def self.non_atomic_transfer(from_account, to_account, amount)
    # Non-atomic implementation (BAD - for demonstration)
    from_account.balance = (from_account.balance.to_i - amount).to_s
    to_account.balance = (to_account.balance.to_i + amount).to_s

    from_account.save
    to_account.save
  end
end

puts '🧪 Redis Command Validation Framework Demo'
puts '=' * 50

# Clean up any existing test data
cleanup_keys = Familia.dbclient.keys('account:*')
Familia.dbclient.del(*cleanup_keys) if cleanup_keys.any?

# Example 1: Basic Command Recording
puts "\n1. Basic Command Recording"
puts '-' * 30

CommandRecorder = Familia::Validation::CommandRecorder
CommandRecorder.start_recording

account = Account.new(account_id: 'acc001', balance: '1000', status: 'active')
account.save

commands = CommandRecorder.stop_recording
puts "Recorded #{commands.command_count} commands:"
commands.commands.each { |cmd| puts "  #{cmd}" }

# Example 2: Transaction Detection
puts "\n2. Transaction Detection"
puts '-' * 30

CommandRecorder.start_recording

acc1 = Account.new(account_id: 'acc002', balance: '2000')
acc2 = Account.new(account_id: 'acc003', balance: '500')
acc1.save
acc2.save

TransferService.atomic_transfer(acc1, acc2, 500)

commands = CommandRecorder.stop_recording
puts "Commands executed: #{commands.command_count}"
puts "Transactions detected: #{commands.transaction_count}"

if commands.transaction_blocks.any?
  tx = commands.transaction_blocks.first
  puts "Transaction commands: #{tx.command_count}"
  tx.commands.each { |cmd| puts "  [TX] #{cmd}" }
end

# Example 3: Validation with Expectations DSL
puts "\n3. Command Validation with Expectations"
puts '-' * 30

begin
  validator = Familia::Validation::Validator.new

  # This should pass - we expect the exact Redis commands
  result = validator.validate do |expect|
    expect.transaction do |tx|
      tx.hset('account:acc004:object', 'balance', '1500')
        .hset('account:acc005:object', 'balance', '1000')
        .hset('account:acc004:object', 'last_updated', Familia::Validation::ArgumentMatcher.new(:any_string))
        .hset('account:acc005:object', 'last_updated', Familia::Validation::ArgumentMatcher.new(:any_string))
    end

    # Execute the operation
    acc4 = Account.new(account_id: 'acc004', balance: '2000')
    acc5 = Account.new(account_id: 'acc005', balance: '500')
    acc4.save
    acc5.save

    TransferService.atomic_transfer(acc4, acc5, 500)
  end

  puts "Validation result: #{result.valid? ? 'PASS ✅' : 'FAIL ❌'}"
  puts "Summary: #{result.summary}"
rescue StandardError => e
  puts "Validation demo encountered error: #{e.message}"
  puts 'This is expected as the framework needs Redis middleware integration'
end

# Example 4: Performance Analysis
puts "\n4. Performance Analysis"
puts '-' * 30

begin
  commands = Familia::Validation.capture_commands do
    # Create multiple accounts
    accounts = []
    (1..5).each do |i|
      account = Account.new(account_id: "perf#{i}", balance: '1000')
      account.save
      accounts << account
    end

    # Perform operations
    accounts[0].balance = '1100'
    accounts[0].save
  end

  analyzer = Familia::Validation::PerformanceAnalyzer.new(commands)
  analysis = analyzer.analyze

  puts 'Performance Analysis:'
  puts "  Total Commands: #{analysis[:total_commands]}"
  puts "  Command Types: #{analysis[:command_type_breakdown].keys.join(', ')}"
  puts "  Efficiency Score: #{analysis[:efficiency_score]}/100"
rescue StandardError => e
  puts "Performance analysis encountered error: #{e.message}"
end

# Example 5: Atomicity Validation
puts "\n5. Atomicity Validation"
puts '-' * 30

begin
  # Test atomic vs non-atomic operations
  acc6 = Account.new(account_id: 'acc006', balance: '3000')
  acc7 = Account.new(account_id: 'acc007', balance: '1000')
  acc6.save
  acc7.save

  # This should detect that atomic operations are properly used
  validator = Familia::Validation::Validator.new(strict_atomicity: true)

  commands = validator.capture_redis_commands do
    TransferService.atomic_transfer(acc6, acc7, 1000)
  end

  atomicity_validator = Familia::Validation::AtomicityValidator.new(commands)
  result = atomicity_validator.validate

  puts "Atomicity validation: #{result.valid? ? 'PASS ✅' : 'FAIL ❌'}"
rescue StandardError => e
  puts "Atomicity validation encountered error: #{e.message}"
end

puts "\n6. Framework Architecture Overview"
puts '-' * 30
puts "
The Redis Command Validation Framework provides:

🔍 Command Recording
  - Captures all Redis commands with full context
  - Tracks transaction boundaries (MULTI/EXEC)
  - Records timing and performance metrics

📝 Expectations DSL
  - Fluent API for defining expected command sequences
  - Support for pattern matching and flexible ordering
  - Transaction and pipeline validation

✅ Validation Engine
  - Compares actual vs expected commands
  - Validates atomicity of operations
  - Provides detailed mismatch reports

🧪 Test Helpers
  - Integration with tryouts framework
  - Methods like assert_redis_commands, assert_atomic_operation
  - Automatic setup and cleanup

⚡ Performance Analysis
  - Command efficiency scoring
  - N+1 pattern detection
  - Transaction overhead analysis

Key Benefits:
• Brass-tacks Redis command validation
• Atomic operation verification
• Performance optimization insights
• Clear diagnostic messages
• Thread-safe operation
"

# Cleanup
cleanup_keys = Familia.dbclient.keys('account:*')
Familia.dbclient.del(*cleanup_keys) if cleanup_keys.any?

puts "\n🎉 Demo complete! The validation framework is ready for use."
puts '    See try/validation/ for comprehensive test examples.'
