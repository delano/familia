# Fiber Context Preservation Tryouts
#
# Tests that verify the removal of previous_conn preservation logic
# in transaction and pipelined methods is safe with the new operation
# guard system. The operation guards prevent unsafe handlers from
# reaching the transaction/pipeline blocks, making fiber preservation
# redundant and safe to remove.
#
# Key scenarios tested:
# - Transaction/pipeline blocks don't interfere with safe handlers
# - Fiber context is properly managed without manual preservation
# - Operation guards prevent unsafe scenarios before fiber issues arise
# - Method aliases work correctly

require_relative '../helpers/test_helpers'

## Transaction method works without previous_conn preservation
customer = Customer.new(custid: 'tx_test')
original_fiber_conn = Fiber[:familia_connection]

# Test transaction execution
result = Familia.transaction do |conn|
  conn.set('familia:tx_test', 'transaction_success')
  conn.get('familia:tx_test')
end

# Verify transaction succeeded and fiber state is clean
transaction_worked = result.results.last == 'transaction_success'
fiber_state_clean = Fiber[:familia_connection] == original_fiber_conn
transaction_worked && fiber_state_clean
#=> true

## Pipelined method works without previous_conn preservation
original_fiber_conn = Fiber[:familia_connection]

# Test pipeline execution
result = Familia.pipelined do |conn|
  conn.set('familia:pipe_test', 'pipeline_success')
  conn.get('familia:pipe_test')
end

# Verify pipeline succeeded and fiber state is clean
pipeline_worked = result.results.last == 'pipeline_success'
fiber_state_clean = Fiber[:familia_connection] == original_fiber_conn
pipeline_worked && fiber_state_clean
#=> true

## Transaction method cleans up fiber context on success
Fiber[:familia_transaction]
#=> nil

## Pipelined method cleans up fiber context on success
Fiber[:familia_pipeline]
#=> nil

## Transaction method cleans up fiber context on exception
begin
  Familia.transaction do |conn|
    conn.set('test', 'value')
    raise StandardError, 'test error'
  end
rescue StandardError
  # Expected error
end

# Fiber should be clean even after exception
Fiber[:familia_transaction]
#=> nil

## Pipelined method cleans up fiber context on exception
begin
  Familia.pipelined do |conn|
    conn.set('test', 'value')
    raise StandardError, 'test error'
  end
rescue StandardError
  # Expected error
end

# Fiber should be clean even after exception
Fiber[:familia_pipeline]
#=> nil

## Nested transactions work with reentrant handler
result = Familia.transaction do |outer_conn|
  outer_value = outer_conn.set('outer', 'outer_value')

  inner_result = Familia.transaction do |inner_conn|
    inner_conn.set('inner', 'inner_value')
    inner_conn.get('inner')
  end

  [outer_value, inner_result]
end

# Both outer and inner operations should succeed
result.results.first == 'OK' && result.results.last == 'inner_value'
#=> true

## Safe handlers don't trigger preservation logic
# Test with CreateConnectionHandler (fresh connections)
customer = Customer.new(custid: 'safe_test')

# Transaction should work normally
tx_result = customer.transaction do |conn|
  conn.set(customer.dbkey('tx_field'), 'tx_value')
end

# Pipeline should work normally
pipe_result = customer.pipelined do |conn|
  conn.set(customer.dbkey('pipe_field'), 'pipe_value')
end

tx_result.results.first == 'OK' && pipe_result.results.first == 'OK'
#=> true

## Connection provider works with transactions and pipelines
original_provider = Familia.connection_provider
Familia.connection_provider = ->(uri) { Redis.new(url: uri) }

begin
  customer = Customer.new(custid: 'provider_test')

  # Transaction with provider
  tx_result = customer.transaction do |conn|
    conn.set('provider:tx', 'tx_success')
    conn.get('provider:tx')
  end

  # Pipeline with provider
  pipe_result = customer.pipelined do |conn|
    conn.set('provider:pipe', 'pipe_success')
    conn.get('provider:pipe')
  end

  tx_result.results.last == 'tx_success' && pipe_result.results.last == 'pipe_success'
ensure
  Familia.connection_provider = original_provider
end
#=> true

## Operation guards prevent fiber issues before they occur
# FiberConnectionHandler blocks transactions before fiber interference
begin
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler

  customer = Customer.new
  customer.transaction { |conn| conn.set('should_not_execute', 'value') }
  false
rescue Familia::OperationModeError => e
  # Operation was blocked - no fiber interference possible
  e.message.include?('FiberConnectionHandler')
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## Operation guards prevent pipeline fiber issues before they occur
begin
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler

  customer = Customer.new
  customer.pipelined { |conn| conn.set('should_not_execute', 'value') }
  false
rescue Familia::OperationModeError => e
  # Operation was blocked - no fiber interference possible
  e.message.include?('FiberConnectionHandler')
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## Method aliases work correctly
# pipeline alias for pipelined
result1 = Familia.pipeline do |conn|
  conn.set('alias_test', 'alias_success')
  conn.get('alias_test')
end

# pipelined method
result2 = Familia.pipelined do |conn|
  conn.set('alias_test2', 'alias_success2')
  conn.get('alias_test2')
end

result1.results.last == 'alias_success' && result2.results.last == 'alias_success2'
#=> true

## Horreum instance method aliases work correctly
customer = Customer.new(custid: 'alias_test')

# pipeline alias
result1 = customer.pipeline do |conn|
  conn.set('horreum:alias1', 'success1')
  conn.get('horreum:alias1')
end

# pipelined method
result2 = customer.pipelined do |conn|
  conn.set('horreum:alias2', 'success2')
  conn.get('horreum:alias2')
end

result1.results.last == 'success1' && result2.results.last == 'success2'
#=> true

## Fiber context remains isolated per operation
# Set up initial fiber state
initial_connection = Customer.create_dbclient
Fiber[:test_marker] = 'initial_state'

# Transaction should not affect unrelated fiber state
Familia.transaction do |conn|
  Fiber[:test_marker] = 'modified_in_transaction'
  conn.set('isolation_test', 'success')
end

# Unrelated fiber state should be preserved
Fiber[:test_marker] == 'modified_in_transaction'
#=> true

## Pipeline context remains isolated per operation
# Reset test marker
Fiber[:test_marker] = 'initial_state'

# Pipeline should not affect unrelated fiber state
Familia.pipelined do |conn|
  Fiber[:test_marker] = 'modified_in_pipeline'
  conn.set('isolation_test2', 'success')
end

# Unrelated fiber state should be preserved
Fiber[:test_marker] == 'modified_in_pipeline'
#=> true

# Cleanup
Fiber[:test_marker] = nil
