# Handler Constraint Methods Tryouts
#
# Tests that each connection handler class correctly defines its operation
# constraints through class methods. These constraints determine what Redis
# operations are safe for each connection type:
#
# - Single connections (middleware/cached) → unsafe for multi-mode operations
# - Fresh connections (provider/create) → safe for all operations
# - Transaction connections → safe for reentrant transactions only

require_relative '../helpers/test_helpers'

## FiberTransactionHandler constraints
Familia::Connection::FiberTransactionHandler.allows_transaction?
#=> :reentrant

## FiberTransactionHandler blocks pipelines
Familia::Connection::FiberTransactionHandler.allows_pipeline?
#=> false

## FiberConnectionHandler blocks transactions
Familia::Connection::FiberConnectionHandler.allows_transaction?
#=> false

## FiberConnectionHandler blocks pipelines
Familia::Connection::FiberConnectionHandler.allows_pipeline?
#=> false

## DefaultConnectionHandler blocks transactions
Familia::Connection::DefaultConnectionHandler.allows_transaction?
#=> false

## DefaultConnectionHandler blocks pipelines
Familia::Connection::DefaultConnectionHandler.allows_pipeline?
#=> false

## ProviderConnectionHandler allows transactions
Familia::Connection::ProviderConnectionHandler.allows_transaction?
#=> true

## ProviderConnectionHandler allows pipelines
Familia::Connection::ProviderConnectionHandler.allows_pipeline?
#=> true

## CreateConnectionHandler allows transactions
Familia::Connection::CreateConnectionHandler.allows_transaction?
#=> true

## CreateConnectionHandler allows pipelines
Familia::Connection::CreateConnectionHandler.allows_pipeline?
#=> true

## BaseConnectionHandler defaults to allow all
Familia::Connection::BaseConnectionHandler.allows_transaction?
#=> true

## BaseConnectionHandler defaults to allow all pipelines
Familia::Connection::BaseConnectionHandler.allows_pipeline?
#=> true
