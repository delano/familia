# Transaction Mode: Strict Tryouts
#
# Tests strict transaction mode behavior where operations fail fast
# when connection handlers don't support transactions.
#
# Strict mode: Raises OperationModeError when transaction unavailable

require_relative '../../support/helpers/test_helpers'

# Test class for strict mode testing
class StrictModeTestCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
end

## Strict mode can be configured
Familia.configure { |config| config.transaction_mode = :strict }
Familia.transaction_mode
#=> :strict

## Strict mode raises error with CachedConnectionHandler

# Force CachedConnectionHandler
StrictModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

customer = StrictModeTestCustomer.new(custid: 'strict_test')
customer.transaction do |conn|
  conn.hset(customer.dbkey, 'name', 'Should Not Work')
end

#=:> Familia::OperationModeError
#=~> /Cannot start transaction with/
#=~> /CachedConnectionHandler/

## Clear the dbclient instance var
StrictModeTestCustomer.remove_instance_variable(:@dbclient)
#=*>

## Strict mode raises error with FiberConnectionHandler
begin
  # Simulate middleware connection
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  customer = StrictModeTestCustomer.new(custid: 'fiber_test')
  customer.transaction { |conn| conn.set('test', 'value') }
  false
rescue Familia::OperationModeError => e
  e.message.include?('FiberConnectionHandler')
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## Strict mode allows normal transactions with CreateConnectionHandler
begin
  customer = StrictModeTestCustomer.new(custid: 'normal_test')
  result = customer.transaction do |conn|
    conn.hset(customer.dbkey, 'type', 'normal transaction')
    conn.hget(customer.dbkey, 'type')
  end
  result.is_a?(MultiResult) && result.results.last == 'normal transaction'
end
#=> true

## Strict mode works with ProviderConnectionHandler
original_provider = Familia.connection_provider
begin
  Familia.connection_provider = ->(uri) { Redis.new(url: uri) }
  customer = StrictModeTestCustomer.new(custid: 'provider_test')
  result = customer.transaction do |conn|
    conn.hset(customer.dbkey, 'source', 'provider')
    conn.hget(customer.dbkey, 'source')
  end
  result.is_a?(MultiResult) && result.results.last == 'provider'
ensure
  Familia.connection_provider = original_provider
end
#=> true

## Global transactions respect strict mode with cached connections
begin
  # Set a cached connection on the Familia module itself would be complex
  # Instead test that cached connections on models affect their transactions
  StrictModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = StrictModeTestCustomer.new(custid: 'global_strict_test')
  customer.transaction do |conn|
    conn.set('should_fail', 'value')
  end
  false
rescue Familia::OperationModeError
  true
ensure
  StrictModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true
