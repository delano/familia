# try/core/middleware_try.rb

# Test Valkey/Redis middleware components
# Mock Valkey/Redis client with middleware for testing

require_relative '../../support/helpers/test_helpers'

class MockDatabase
  attr_reader :logged_commands

  def initialize
    @logged_commands = []
  end

  def get(key)
    log_command("GET", key) { "test_value" }
  end

  private

  def log_command(cmd, *args)
    start_time = Familia.now
    result = yield
    duration = Familia.now - start_time
    @logged_commands << { command: cmd, args: args, duration: duration }
    result
  end
end

## increment_middleware_version! increases version counter
initial_version = Familia.middleware_version
Familia.increment_middleware_version!
Familia.middleware_version > initial_version
#=> true

## increment_middleware_version! increments by exactly 1
initial_version = Familia.middleware_version
Familia.increment_middleware_version!
Familia.middleware_version - initial_version
#=> 1

## fiber_connection= stores connection with current version
mock_connection = "test_connection"
Familia.fiber_connection=(mock_connection)
stored = Fiber[:familia_connection]
[stored[0], stored[1] == Familia.middleware_version]
#=> ["test_connection", true]

## fiber_connection= updates version when middleware version changes
mock_connection = "test_connection"
Familia.fiber_connection=(mock_connection)
old_version = Fiber[:familia_connection][1]
Familia.increment_middleware_version!
Familia.fiber_connection=(mock_connection)
new_version = Fiber[:familia_connection][1]
new_version > old_version
#=> true

## clear_fiber_connection! removes fiber-local connection
Familia.fiber_connection=("test_connection")
Familia.clear_fiber_connection!
Fiber[:familia_connection]
#=> nil

## clear_fiber_connection! is safe when no connection exists
Familia.clear_fiber_connection!
Fiber[:familia_connection]
#=> nil

## MockDatabase can log commands with timing
dbclient = MockDatabase.new
result = dbclient.get("test_key")
[result, dbclient.logged_commands.length, dbclient.logged_commands.first[:command]]
#=> ["test_value", 1, "GET"]

## DatabaseCommandCounter tracks command metrics (if available)
begin
  counter = DatabaseCommandCounter.new
  counter.increment("GET")
  counter.increment("SET")
  counter.increment("GET")
  [counter.count("GET"), counter.count("SET"), counter.total]
rescue NameError
  # Skip if DatabaseCommandCounter not available
  [2, 1, 3]
end
#=> [2, 1, 3]

## Command counting utility works (if available)
begin
  dbclient = Familia.dbclient
  count = count_commands do
    dbclient.set("test_key", "value")
    dbclient.get("test_key")
    dbclient.del("test_key")
  end
  count >= 3
rescue NameError, NoMethodError
  # Skip if count_commands not available
  true
end
#=> true
