# try/integration/connection/transaction_modes_try.rb
#
# frozen_string_literal: true

# Transaction Modes Tryouts
#
# Tests the configurable transaction mode system that provides graceful fallback
# when connection handlers don't support transactions. Three modes available:
#
# - :strict (default): Raise OperationModeError when transaction unavailable
# - :warn: Log warning and execute commands individually with IndividualCommandProxy
# - :permissive: Silently execute commands individually
#
# The IndividualCommandProxy executes Redis commands immediately instead of queuing
# them in a transaction, maintaining the same MultiResult interface for consistency.

require_relative '../../support/helpers/test_helpers'

# Setup - ensure clean state
@original_transaction_mode = Familia.transaction_mode
@test_customer_class = nil

# Create a test customer class for isolation
class TransactionModeTestCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
  field :email
end

## Default transaction mode is warn (user-friendly)
Familia.transaction_mode
#=> :warn

## Transaction mode can be configured to warn
Familia.configure do |config|
  config.transaction_mode = :warn
end
Familia.transaction_mode
#=> :warn

## Transaction mode can be configured to permissive
Familia.configure do |config|
  config.transaction_mode = :permissive
end
Familia.transaction_mode
#=> :permissive

## Reset to strict mode for remaining tests
Familia.configure { |config| config.transaction_mode = :strict }

## Strict mode raises error with CachedConnectionHandler
begin
  # Ensure we're in strict mode first
  Familia.configure { |config| config.transaction_mode = :strict }

  # Force CachedConnectionHandler by setting @dbclient
  TransactionModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = TransactionModeTestCustomer.new(custid: 'strict_test')
  customer.transaction do |conn|
    conn.hset(customer.dbkey, 'name', 'Should Not Work')
  end
  false  # Should not reach here
rescue Familia::OperationModeError => e
  e.message.include?('Cannot start transaction with') && e.message.include?('CachedConnectionHandler')
ensure
  # Clean up cached connection
  TransactionModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Warn mode logs warning and executes individual commands
begin
  Familia.configure { |config| config.transaction_mode = :warn }

  # Force CachedConnectionHandler
  TransactionModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = TransactionModeTestCustomer.new(custid: 'warn_test')

  # Capture log output would be ideal, but test the core functionality
  result = customer.transaction do |conn|
    # This should be an IndividualCommandProxy
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'name', 'Warn Mode Works') &&
    conn.hget(customer.dbkey, 'name')
  end

  # Should return MultiResult with individual command results
  result.is_a?(MultiResult) && result.results.last == 'Warn Mode Works'
ensure
  TransactionModeTestCustomer.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Permissive mode silently executes individual commands
begin
  Familia.configure { |config| config.transaction_mode = :permissive }

  # Force CachedConnectionHandler
  TransactionModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = TransactionModeTestCustomer.new(custid: 'permissive_test')

  result = customer.transaction do |conn|
    # Should be IndividualCommandProxy
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'email', 'permissive@example.com') &&
    conn.hget(customer.dbkey, 'email')
  end

  # Should return MultiResult
  result.is_a?(MultiResult) && result.results.last == 'permissive@example.com'
ensure
  TransactionModeTestCustomer.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Normal transactions still work with CreateConnectionHandler
begin
  customer = TransactionModeTestCustomer.new(custid: 'normal_test')

  result = customer.transaction do |conn|
    # Should be Redis::MultiConnection for normal transactions
    conn.class == Redis::MultiConnection &&
    conn.hset(customer.dbkey, 'type', 'normal transaction') &&
    conn.hget(customer.dbkey, 'type')
  end

  result.is_a?(MultiResult) && result.results.last == 'normal transaction'
end
#=> true

## IndividualCommandProxy collects results correctly
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  TransactionModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = TransactionModeTestCustomer.new(custid: 'proxy_test')

  result = customer.transaction do |conn|
    conn.hset(customer.dbkey, 'field1', 'value1')
    conn.hget(customer.dbkey, 'field1')
  end

  # Check that results are collected and it's a MultiResult
  result.is_a?(MultiResult) && result.results.size >= 2
ensure
  TransactionModeTestCustomer.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## MultiResult success detection works with individual commands
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  TransactionModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = TransactionModeTestCustomer.new(custid: 'success_test')

  result = customer.transaction do |conn|
    conn.hset(customer.dbkey, 'status', 'active')  # Returns 1
  end

  # Should be successful since 1 is considered success
  result.successful?
ensure
  TransactionModeTestCustomer.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Global transaction methods also respect transaction modes
begin
  Familia.configure { |config| config.transaction_mode = :permissive }

  # Force a handler that doesn't support transactions
  original_provider = Familia.connection_provider
  test_connection = Familia.create_dbclient
  Familia.connection_provider = ->(_uri) { test_connection }

  # Global transaction should also fallback
  result = Familia.transaction do |conn|
    conn.set('global_test_key', 'global_test_value')
    conn.get('global_test_key')
  end

  result.is_a?(MultiResult) && result.results.last == 'global_test_value'
ensure
  Familia.connection_provider = original_provider
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Transaction fallback preserves connection context
begin
  Familia.configure { |config| config.transaction_mode = :permissive }

  # Test with logical database setting
  class DatabaseTestCustomer < Familia::Horreum
    logical_database 5
    identifier_field :custid
    field :custid
  end

  DatabaseTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)
  customer = DatabaseTestCustomer.new(custid: 'db_test')

  result = customer.transaction do |conn|
    # Commands should execute on the correct database
    conn.set('db_test_key', 'db_test_value')
    conn.get('db_test_key')
  end

  result.results.last == 'db_test_value'
ensure
  DatabaseTestCustomer.remove_instance_variable(:@dbclient) if DatabaseTestCustomer.instance_variable_defined?(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Transaction modes work with nested calls
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  TransactionModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = TransactionModeTestCustomer.new(custid: 'nested_test')

  # Test that nested transactions work
  outer_result = customer.transaction do |outer_conn|
    outer_conn.hset(customer.dbkey, 'outer', 'value')

    inner_result = customer.transaction do |inner_conn|
      inner_conn.hset(customer.dbkey, 'inner', 'nested')
    end

    # Inner transaction should return MultiResult
    inner_result.is_a?(MultiResult)
  end

  # Outer transaction should also return MultiResult
  outer_result.is_a?(MultiResult)
ensure
  TransactionModeTestCustomer.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

# Cleanup - restore original transaction mode
Familia.configure { |config| config.transaction_mode = @original_transaction_mode }
