# try/integration/connection/transaction_mode_permissive_try.rb
#
# frozen_string_literal: true

# Transaction Mode: Permissive Tryouts
#
# Tests permissive transaction mode behavior where operations silently
# execute commands individually when transactions are unavailable.
#
# Permissive mode: Silently uses IndividualCommandProxy for fallback

require_relative '../../support/helpers/test_helpers'

# Test class for permissive mode testing
class PermissiveModeTestCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
  field :status
end

## Permissive mode can be configured
Familia.configure { |config| config.transaction_mode = :permissive }
Familia.transaction_mode
#=> :permissive

## Permissive mode silently executes individual commands with CachedConnectionHandler
begin
  # Force CachedConnectionHandler
  PermissiveModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = PermissiveModeTestCustomer.new(custid: 'permissive_test')
  result = customer.transaction do |conn|
    # Should be IndividualCommandProxy
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'name', 'Permissive Mode Works') &&
    conn.hget(customer.dbkey, 'name')
  end

  result.is_a?(MultiResult) && result.results.last == 'Permissive Mode Works'
ensure
  PermissiveModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Permissive mode works silently with FiberConnectionHandler
begin
  # Simulate middleware connection
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  customer = PermissiveModeTestCustomer.new(custid: 'fiber_permissive_test')

  result = customer.transaction do |conn|
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.hset(customer.dbkey, 'source', 'fiber_permissive') &&
    conn.hget(customer.dbkey, 'source')
  end

  result.is_a?(MultiResult) && result.results.last == 'fiber_permissive'
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## Permissive mode still uses normal transactions when available
begin
  customer = PermissiveModeTestCustomer.new(custid: 'normal_permissive_test')
  result = customer.transaction do |conn|
    # Should be Redis::MultiConnection for normal transactions
    conn.class == Redis::MultiConnection &&
    conn.hset(customer.dbkey, 'type', 'normal in permissive mode') &&
    conn.hget(customer.dbkey, 'type')
  end
  result.is_a?(MultiResult) && result.results.last == 'normal in permissive mode'
end
#=> true

## Permissive mode handles complex operations silently
begin
  PermissiveModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = PermissiveModeTestCustomer.new(custid: 'complex_permissive_test')
  result = customer.transaction do |conn|
    # Multiple operations that would normally be atomic
    conn.hset(customer.dbkey, 'status', 'processing')
    conn.hset(customer.dbkey, 'updated_at', Time.now.to_i)
    conn.hset(customer.dbkey, 'version', '1.0')
    conn.hget(customer.dbkey, 'status')
  end

  result.is_a?(MultiResult) && result.results.last == 'processing'
ensure
  PermissiveModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Permissive mode works with nested calls
begin
  PermissiveModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = PermissiveModeTestCustomer.new(custid: 'nested_permissive_test')

  outer_result = customer.transaction do |outer_conn|
    outer_conn.hset(customer.dbkey, 'outer', 'value')

    inner_result = customer.transaction do |inner_conn|
      inner_conn.hset(customer.dbkey, 'inner', 'nested_value')
    end

    # Both should return MultiResult
    inner_result.is_a?(MultiResult)
  end

  outer_result.is_a?(MultiResult)
ensure
  PermissiveModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Batch operations work silently in permissive mode
begin
  PermissiveModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = PermissiveModeTestCustomer.new(custid: 'batch_permissive_test')

  # Large batch that would normally be atomic
  result = customer.transaction do |conn|
    10.times do |i|
      conn.hset(customer.dbkey, "field_#{i}", "value_#{i}")
    end
    conn.hget(customer.dbkey, 'field_9')
  end

  result.is_a?(MultiResult) && result.results.last == 'value_9'
ensure
  PermissiveModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true

## Save operations work in permissive mode
begin
  PermissiveModeTestCustomer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = PermissiveModeTestCustomer.new(
    custid: 'save_permissive_test',
    name: 'Permissive Save User',
    status: 'active'
  )

  # Should save successfully using individual commands
  save_result = customer.save
  save_result && customer.exists?
ensure
  PermissiveModeTestCustomer.remove_instance_variable(:@dbclient)
end
#=> true
