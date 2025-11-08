# try/integration/connection/transaction_mode_warn_try.rb
#
# frozen_string_literal: true

# Transaction Mode: Warn Tryouts
#
# Tests warn transaction mode behavior where operations log a warning
# and execute commands individually when transactions are unavailable.
#
# Warn mode: Logs warning and uses IndividualCommandProxy for fallback

require_relative '../../support/helpers/test_helpers'

# Test class for warn mode testing
class WarnModeTestCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
  field :email
end

## Warn mode can be configured
Familia.configure { |config| config.transaction_mode = :warn }
Familia.transaction_mode
#=> :warn

## Warn mode executes individual commands with CachedConnectionHandler
begin
  # Force CachedConnectionHandler
  WarnModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = WarnModeTestCustomer.new(custid: 'warn_test')
  result = customer.transaction do |conn|
    # Should be IndividualCommandProxy
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'name', 'Warn Mode Works') &&
    conn.hget(customer.dbkey, 'name')
  end

  result.is_a?(MultiResult) && result.results.last == 'Warn Mode Works'
ensure
  WarnModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Warn mode executes individual commands with FiberConnectionHandler
begin
  # Simulate middleware connection
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  customer = WarnModeTestCustomer.new(custid: 'fiber_warn_test')

  result = customer.transaction do |conn|
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'source', 'fiber_warn') &&
    conn.hget(customer.dbkey, 'source')
  end

  result.is_a?(MultiResult) && result.results.last == 'fiber_warn'
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## Warn mode still uses normal transactions with CreateConnectionHandler
begin
  customer = WarnModeTestCustomer.new(custid: 'normal_warn_test')
  result = customer.transaction do |conn|
    # Should be Redis::MultiConnection for normal transactions
    conn.class == Redis::MultiConnection &&
    conn.hset(customer.dbkey, 'type', 'normal in warn mode') &&
    conn.hget(customer.dbkey, 'type')
  end
  result.is_a?(MultiResult) && result.results.last == 'normal in warn mode'
end
#=> true

## IndividualCommandProxy collects results correctly in warn mode
begin
  WarnModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = WarnModeTestCustomer.new(custid: 'proxy_warn_test')
  result = customer.transaction do |conn|
    conn.hset(customer.dbkey, 'field1', 'value1')
    conn.hset(customer.dbkey, 'field2', 'value2')
    conn.hget(customer.dbkey, 'field1')
    conn.hget(customer.dbkey, 'field2')
  end

  # Check that results are collected properly
  result.is_a?(MultiResult) &&
  result.results.size == 4 &&
  result.results.include?('value1') &&
  result.results.include?('value2')
ensure
  WarnModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Save operations work in warn mode with fallback
begin
  WarnModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = WarnModeTestCustomer.new(
    custid: 'save_warn_test',
    name: 'Save Test User',
    email: 'save@example.com'
  )

  # Save should work using individual commands
  save_result = customer.save
  save_result && customer.exists?
ensure
  WarnModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Model transactions respect warn mode with cached connections
begin
  # Test that cached connections on models respect warn mode
  WarnModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = WarnModeTestCustomer.new(custid: 'model_warn_test')
  result = customer.transaction do |conn|
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'mode', 'warn_fallback') &&
    conn.hget(customer.dbkey, 'mode')
  end

  result.is_a?(MultiResult) && result.results.last == 'warn_fallback'
ensure
  WarnModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true
