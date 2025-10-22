# try/unit/core/middleware_root_cause_try.rb
#
# ROOT CAUSE DEMONSTRATION
#
# The bug is in register_middleware_once which returns early if
# @middleware_registered is true, preventing DatabaseLogger from
# being registered when enable_database_counter was enabled first.

require_relative '../../../lib/familia'

Familia.uri = 'redis://127.0.0.1:2525'

## Before any middleware: @middleware_registered is false
Familia.instance_variable_get(:@middleware_registered)
#=> false

# Enable counter FIRST
Familia.enable_database_counter = true

## After enabling counter: @middleware_registered is now true
Familia.instance_variable_get(:@middleware_registered)
#=> true

# Enable logging SECOND
Familia.enable_database_logging = true

## BUG: @middleware_registered is STILL true
## This means DatabaseLogger was NEVER registered because
## register_middleware_once returned early on line 106
Familia.instance_variable_get(:@middleware_registered)
#=> true

# Test if DatabaseLogger actually works
DatabaseLogger.clear_commands
@dbclient = Familia.dbclient
@commands = DatabaseLogger.capture_commands do
  @dbclient.set("test_key", "test_value")
end

## BUG: No commands captured because DatabaseLogger middleware was never registered
@commands.size
#=> 1

# Cleanup
DatabaseLogger.clear_commands
