# try/unit/core/middleware_isolation_test2_try.rb
#
# Test the EXACT sequence from test_helpers.rb
# Key difference: test_helpers.rb sets enable_database_logging BEFORE require familia

require 'digest'

# This is the KEY DIFFERENCE: test_helpers.rb requires familia first
require_relative '../../../lib/familia'

# THEN it enables middleware
Familia.enable_database_logging = true
Familia.enable_database_counter = true
Familia.uri = 'redis://127.0.0.1:2525'

# Define a class (like test_helpers.rb does)
class TestBone < Familia::Horreum
  identifier_field :token
  field :token
  field :name
  list :owners
  set :tags
end

# Create an instance at module level (like test_helpers.rb does)
@test_bone = TestBone.new
@test_bone.token = 'test123'

# NOW call reconnect (this is what the bug test does)
Familia.connection_provider = nil
Familia.reconnect!
DatabaseLogger.clear_commands

## Middleware captures commands after reconnect
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
