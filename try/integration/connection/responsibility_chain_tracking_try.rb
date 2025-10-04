# ResponsibilityChain Handler Tracking Tryouts
#
# Tests that the ResponsibilityChain correctly tracks which handler provided
# each connection by setting Fiber[:familia_connection_handler_class]. This enables
# operation mode guards to enforce constraints based on connection source.
#
# The chain should:
# - Try handlers in order until one returns a connection
# - Set Fiber[:familia_connection_handler_class] to the successful handler's class
# - Return the connection from the successful handler
# - Return nil if no handler provides a connection

require_relative '../../support/helpers/test_helpers'

# Setup - clear any existing fiber state
Fiber[:familia_connection_handler_class] = nil
Fiber[:familia_connection] = nil

## Chain tracks CreateConnectionHandler for normal connections
customer = Customer.new
customer.custid = 'tracking_test'
connection = customer.dbclient
Fiber[:familia_connection_handler_class]
#=> Familia::Connection::CreateConnectionHandler

## Chain tracks FiberConnectionHandler for middleware connections
begin
  test_conn = Customer.create_dbclient
  Fiber[:familia_connection] = [test_conn, Familia.middleware_version]

  customer = Customer.new
  customer.custid = 'fiber_test'
  connection = customer.dbclient
  Fiber[:familia_connection_handler_class]
ensure
  Fiber[:familia_connection] = nil
  Fiber[:familia_connection_handler_class] = nil
end
#=> Familia::Connection::FiberConnectionHandler

## Chain tracks ProviderConnectionHandler for connection providers
original_provider = Familia.connection_provider
begin
  Familia.connection_provider = ->(uri) { Redis.new(url: uri) }

  customer = Customer.new
  customer.custid = 'provider_test'
  connection = customer.dbclient
  Fiber[:familia_connection_handler_class]
ensure
  Familia.connection_provider = original_provider
  Fiber[:familia_connection_handler_class] = nil
end
#=> Familia::Connection::ProviderConnectionHandler

## Chain returns nil when no handler provides connection
# Create a mock chain with handlers that return nil
chain = Familia::Connection::ResponsibilityChain.new
chain.add_handler(Familia::Connection::FiberTransactionHandler.new)
chain.add_handler(Familia::Connection::FiberConnectionHandler.new)

result = chain.handle('test_uri')
result.nil?
#=> true

## Chain sets handler class even when tracking connections
customer = Customer.new
customer.custid = 'final_test'
conn = customer.dbclient
handler_class = Fiber[:familia_connection_handler_class]
handler_class == Familia::Connection::CreateConnectionHandler && !conn.nil?
#=> true
