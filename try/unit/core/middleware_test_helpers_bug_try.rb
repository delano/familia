# try/unit/core/middleware_test_helpers_bug_try.rb

# Minimal reproduction of middleware registration bug
#
# ISSUE: Loading test_helpers.rb before calling Familia.reconnect! causes
# middleware to stop capturing commands, resulting in empty commands array
# and NoMethodError when accessing commands.first.command
#
# ROOT CAUSE: Unknown - something in test_helpers.rb (class definitions or
# object instantiations at module level) breaks middleware registration
# after reconnect!
#
# EVIDENCE:
# - WITHOUT test_helpers: middleware works (commands captured)
# - WITH test_helpers: middleware breaks (0 commands captured)
# - @middleware_registered flag remains true (middleware IS registered globally)
# - RedisClient.register(DatabaseLogger) is called successfully
# - New connections after reconnect! don't pick up middleware
#
# Related: https://github.com/delano/familia/issues/168

require_relative '../../support/helpers/test_helpers'
require 'logger'
require 'stringio'

# Setup: Same as middleware_sampling_try.rb
Familia.connection_provider = nil
Familia.enable_database_logging = true
Familia.reconnect!
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = nil
DatabaseLogger.structured_logging = false

## Middleware is registered globally
Familia.instance_variable_get(:@middleware_registered)
#=> true

## Commands SHOULD be captured after loading test_helpers + reconnect
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands = DatabaseLogger.capture_commands do
  dbclient.set("test_key", "test_value")
end

# BUG: Currently returns 0, should be 1
@commands.size
#=> 1

## Accessing commands.first SHOULD work without NoMethodError
@cmd = @commands.first
# BUG: Currently nil, should be a CommandMessage
@cmd.nil?
#=> false

# Teardown
DatabaseLogger.clear_commands
