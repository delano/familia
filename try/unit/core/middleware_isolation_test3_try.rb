# try/unit/core/middleware_isolation_test3_try.rb
#
# Narrowing down: what breaks middleware?

require_relative '../../../lib/familia'

# Enable middleware AFTER require
Familia.enable_database_logging = true
Familia.uri = 'redis://127.0.0.1:2525'

## Test 1: Middleware works immediately after enabling
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_1 = DatabaseLogger.capture_commands do
  dbclient.set("test_1", "value_1")
end
@commands_1.size
#=> 1

# Define a class
class TestClass < Familia::Horreum
  field :name
end

## Test 2: Middleware still works after class definition
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_2 = DatabaseLogger.capture_commands do
  dbclient.set("test_2", "value_2")
end
@commands_2.size
#=> 1

# Create an instance
@obj = TestClass.new(name: "test")

## Test 3: Middleware still works after instance creation
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_3 = DatabaseLogger.capture_commands do
  dbclient.set("test_3", "value_3")
end
@commands_3.size
#=> 1

# Call reconnect!
Familia.connection_provider = nil
Familia.reconnect!

## Test 4: THIS IS WHERE IT BREAKS - after reconnect!
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_4 = DatabaseLogger.capture_commands do
  dbclient.set("test_4", "value_4")
end
@commands_4.size
#=> 1

# Teardown
DatabaseLogger.clear_commands
