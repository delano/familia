# Operation Mode Guards Tryouts
#
# Tests the connection handler operation mode enforcement that prevents Redis
# mode confusion bugs. Each handler type has specific operation constraints:
#
# - FiberTransactionHandler: Allow reentrant transactions, block pipelines
# - FiberConnectionHandler: Block all multi-mode operations (middleware single conn)
# - CachedConnectionHandler: Block all multi-mode operations (cached single conn)
# - ProviderConnectionHandler: Allow all operations (fresh checkout each time)
# - CreateConnectionHandler: Allow all operations (new connection each time)
#
# This prevents bugs where middleware/cached connections return "QUEUED" instead
# of actual values, breaking conditional logic and business rules.

require_relative '../helpers/test_helpers'

## FiberConnectionHandler blocks transactions in strict mode
begin
  # Ensure we're in strict mode for this test
  Familia.configure { |config| config.transaction_mode = :strict }

  # Simulate middleware connection
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  customer = Customer.new
  customer.transaction { |conn| conn.set('test', 'value') }
  false
rescue Familia::OperationModeError
  true
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## FiberConnectionHandler blocks pipelines
begin
  # Ensure we're in strict mode for this test
  Familia.configure { |config| config.pipeline_mode = :strict }

  # Simulate middleware connection
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  customer = Customer.new
  customer.pipelined { |conn| conn.set('test', 'value') }
  false
rescue Familia::OperationModeError
  true
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

## CreateConnectionHandler allows transactions
begin
  customer = Customer.new
  customer.custid = 'test_tx'
  result = customer.transaction { |conn| conn.set('tx_test', 'success') }
  true
rescue Familia::OperationModeError
  false
end
#=> true

## CreateConnectionHandler allows pipelines
begin
  customer = Customer.new
  customer.custid = 'test_pipe'
  result = customer.dbclient.pipelined { |conn| conn.set('pipe_test', 'success') }
  true
rescue Familia::OperationModeError
  false
end
#=> true

## ProviderConnectionHandler allows all operations
# Set up connection provider
original_provider = Familia.connection_provider
Familia.connection_provider = ->(uri) { Redis.new(url: uri) }

begin
  customer = Customer.new
  customer.custid = 'test_provider'
  tx_result = customer.transaction { |conn| conn.set('provider_tx', 'success') }
  pipe_result = customer.dbclient.pipelined { |conn| conn.set('provider_pipe', 'success') }
  true
rescue Familia::OperationModeError
  false
ensure
  Familia.connection_provider = original_provider
end
#=> true

## Handler class tracking works correctly
customer = Customer.new
customer.dbclient # Trigger connection
Fiber[:familia_connection_handler_class]
#=> Familia::Connection::CreateConnectionHandler

## Error messages are descriptive
begin
  Fiber[:familia_connection] = [Customer.create_dbclient, Familia.middleware_version]
  Fiber[:familia_connection_handler_class] = Familia::Connection::FiberConnectionHandler
  customer = Customer.new
  customer.transaction { }
rescue Familia::OperationModeError => e
  e.message.include?('FiberConnectionHandler') && e.message.include?('connection pools')
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> true

# Transaction Mode Backward Compatibility Tests
# Ensure new configurable transaction modes don't break existing behavior

# Store original transaction mode
@original_transaction_mode = Familia.transaction_mode

## Transaction mode reflects current setting
# Note: May be :warn (default) or :strict (if changed by previous tests)
[:warn, :strict].include?(Familia.transaction_mode)
#=> true

## CachedConnectionHandler still blocks transactions in strict mode
begin
  # Ensure we're in strict mode
  Familia.configure { |config| config.transaction_mode = :strict }

  # Force CachedConnectionHandler
  Customer.instance_variable_set(:@dbclient, Familia.create_dbclient)

  customer = Customer.new
  customer.custid = 'strict_compat_test'
  customer.transaction { |conn| conn.set('should_fail', 'value') }
  false  # Should not reach here
rescue Familia::OperationModeError => e
  e.message.include?('CachedConnectionHandler')
ensure
  Customer.remove_instance_variable(:@dbclient)
end
#=> true

## Normal transactions still work exactly as before
begin
  customer = Customer.new
  customer.custid = 'normal_compat_test'

  result = customer.transaction do |conn|
    conn.set('compat_test', 'success')
    conn.get('compat_test')
  end

  # Should return MultiResult as before
  result.is_a?(MultiResult) && result.results.last == 'success'
end
#=> true

## Pipeline operations maintain existing behavior
begin
  customer = Customer.new
  customer.custid = 'pipeline_compat_test'

  result = customer.pipelined do |conn|
    conn.set('pipe_compat', 'pipeline_success')
    conn.get('pipe_compat')
  end

  result.is_a?(MultiResult) && result.results.last == 'pipeline_success'
end
#=> true

## Connection handler capabilities unchanged for CreateConnectionHandler allows_transaction
Familia::Connection::CreateConnectionHandler.allows_transaction
#=> true

## Connection handler capabilities unchanged for CreateConnectionHandler allows_pipelined
Familia::Connection::CreateConnectionHandler.allows_pipelined
#=> true

## Connection handler capabilities unchanged for CachedConnectionHandler allows_transaction
Familia::Connection::CachedConnectionHandler.allows_transaction
#=> false

## Connection handler capabilities unchanged for CachedConnectionHandler allows_pipelined
Familia::Connection::CachedConnectionHandler.allows_pipelined
#=> false

## Transaction modes don't affect normal connection resolution
begin
  # Change to permissive mode
  Familia.configure { |config| config.transaction_mode = :permissive }

  # Normal operations should still work the same way
  customer = Customer.new
  customer.custid = 'resolution_test'

  # Should still use CreateConnectionHandler for normal transactions
  conn = customer.dbclient
  Fiber[:familia_connection_handler_class] == Familia::Connection::CreateConnectionHandler
ensure
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

# Restore original transaction mode
Familia.configure { |config| config.transaction_mode = @original_transaction_mode }
