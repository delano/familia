# try/unit/core/middleware_redisclient_bug_try.rb
#
# The ROOT CAUSE: RedisClient.register is GLOBAL and PERMANENT
# Once middleware is registered with RedisClient, calling reconnect! and
# register_middleware_once again does NOT re-register the middleware.
#
# The issue is that when reconnect! sets @middleware_registered = false
# and then calls register_middleware_once, it calls RedisClient.register
# AGAIN, but RedisClient already has the middleware registered globally.
#
# However, connections created BEFORE middleware was registered don't
# get the middleware retroactively applied.

require_relative '../../../lib/familia'

# Scenario 1: Enable counter, get connection, then reconnect
Familia.enable_database_counter = true
Familia.uri = 'redis://127.0.0.1:2525'

# This creates a connection WITHOUT DatabaseLogger middleware
# because we haven't enabled it yet
@conn1 = Familia.create_dbclient

## Connection 1 created
@conn1.nil?
#=> false

# Now enable logging
Familia.enable_database_logging = true

# Call reconnect to supposedly apply new middleware
Familia.reconnect!
DatabaseLogger.clear_commands

# Get a NEW connection after reconnect
@conn2 = Familia.create_dbclient

## Connection 2 is different from connection 1
(@conn1.object_id == @conn2.object_id)
#=> false

# Test if conn2 has middleware by executing a command
DatabaseLogger.clear_commands
@commands = DatabaseLogger.capture_commands do
  @conn2.set("test_key", "test_value")
end

## BUG: Commands should be captured on conn2
@commands.size
#=> 1

# Cleanup
@conn1.close
@conn2.close
DatabaseLogger.clear_commands
