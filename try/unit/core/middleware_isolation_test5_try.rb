# try/unit/core/middleware_isolation_test5_try.rb
#
# Testing: Is it enable_database_counter specifically?

require_relative '../../../lib/familia'

# Only enable counter (NOT logging)
Familia.enable_database_counter = true
Familia.uri = 'redis://127.0.0.1:2525'

# Call reconnect!
Familia.connection_provider = nil
Familia.reconnect!

# Now enable logging AFTER reconnect
Familia.enable_database_logging = true
DatabaseLogger.clear_commands

## Test: Does middleware work when counter was enabled before reconnect?
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands = DatabaseLogger.capture_commands do
  dbclient.set("test_key", "test_value")
end
@commands.size
#=> 1

# Teardown
DatabaseLogger.clear_commands
