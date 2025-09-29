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

## FiberConnectionHandler blocks transactions
begin
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
