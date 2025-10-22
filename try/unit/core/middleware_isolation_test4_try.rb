# try/unit/core/middleware_isolation_test4_try.rb
#
# Adding enable_database_counter like test_helpers.rb does

require_relative '../../../lib/familia'

# Enable BOTH middleware flags like test_helpers.rb
Familia.enable_database_logging = true
Familia.enable_database_counter = true  # <-- THIS IS THE DIFFERENCE
Familia.uri = 'redis://127.0.0.1:2525'

# Define a class
class TestClass < Familia::Horreum
  field :name
end

# Create an instance
@obj = TestClass.new(name: "test")

# Call reconnect!
Familia.connection_provider = nil
Familia.reconnect!
DatabaseLogger.clear_commands

## Middleware captures commands after reconnect with counter enabled
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands = DatabaseLogger.capture_commands do
  dbclient.set("test_key", "test_value")
end
@commands.size
#=> 1

## Commands are accessible
@commands.first.nil?
#=> false

# Teardown
DatabaseLogger.clear_commands
