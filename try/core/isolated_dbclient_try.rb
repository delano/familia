# try/core/isolated_dbclient_try.rb

# Tryouts: Isolated connection functionality
#
# Tests for isolated database connections that don't interfere
# with the cached connection pool or existing model connections.

require_relative '../helpers/test_helpers'

# Clean up any existing test data in all test databases
(0..15).each do |db|
  Familia.with_isolated_dbclient(db) do |client|
    client.flushdb
  end
end

## isolated_dbclient creates a new uncached connection
client1 = Familia.isolated_dbclient(0)
client2 = Familia.isolated_dbclient(0)
different_objects = client1.object_id != client2.object_id
client1.close
client2.close
different_objects
#=> true

## isolated_dbclient connects to the correct database
Familia.with_isolated_dbclient(5) do |client|
  client.set("test_key", "test_value")
end

# Verify the key was set in database 5
found_in_db5 = Familia.with_isolated_dbclient(5) do |client|
  client.get("test_key") == "test_value"
end

# Verify the key is NOT in database 0
not_found_in_db0 = Familia.with_isolated_dbclient(0) do |client|
  client.get("test_key").nil?
end

found_in_db5 && not_found_in_db0
#=> true

## isolated_dbclient doesn't affect cached connections
# Set up a cached connection
regular_client = Familia.dbclient(0)
regular_client.set("cached_key", "cached_value")

# Use isolated connection on same database
isolated_result = Familia.with_isolated_dbclient(0) do |client|
  client.set("isolated_key", "isolated_value")
  client.get("cached_key")
end

# Both keys should be accessible
cached_accessible = regular_client.get("cached_key") == "cached_value"
isolated_accessible = regular_client.get("isolated_key") == "isolated_value"

cached_accessible && isolated_accessible && isolated_result == "cached_value"
#=> true

## with_isolated_dbclient properly manages connection lifecycle
# Test by verifying functionality rather than relying on GC/ObjectSpace
captured_clients = []

5.times do |i|
  Familia.with_isolated_dbclient(i) do |client|
    captured_clients << client
    client.set("temp_key_#{i}", "temp_value_#{i}")
    # Verify connection works inside block
    client.ping
  end
end

# Verify all connections worked and created distinct objects
all_worked = captured_clients.size == 5
all_distinct = captured_clients.map(&:object_id).uniq.size == 5
keys_set = Familia.with_isolated_dbclient(0) { |c| c.exists?("temp_key_0") }

all_worked && all_distinct && keys_set
#=> true

## with_isolated_dbclient handles exceptions gracefully
exception_raised = false
database_state_correct = false

begin
  Familia.with_isolated_dbclient(0) do |client|
    client.set("before_error", "value")
    raise "Test exception"
    # This line should not be reached
    client.set("after_error", "should_not_be_set")
  end
rescue => e
  exception_raised = (e.message == "Test exception")
end

# Verify the database state after the exception was caught
if exception_raised
  database_state_correct = Familia.with_isolated_dbclient(0) do |client|
    client.get("before_error") == "value" && client.get("after_error").nil?
  end
end

exception_raised && database_state_correct
#=> true

## isolated connections don't interfere with model connections
class TestModel < Familia::Horreum
  logical_database 3
  identifier_field :name
  field :name
end

# Create a model instance
test_model = TestModel.new(name: "test")
test_model.save

# Use isolated connection to scan a different database
scan_result = Familia.with_isolated_dbclient(5) do |client|
  client.keys("*")
end

# Model should still work correctly
model_accessible = test_model.exists? && test_model.name == "test"
# Don't rely on database 5 being empty since previous tests may have written to it
# Just verify the model still works correctly
scan_result_valid = scan_result.is_a?(Array)

model_accessible && scan_result_valid
#=> true

# Clean up test model and class
test_model.delete!
Familia.unload_member(TestModel)

## isolated_dbclient with Integer argument
client = Familia.isolated_dbclient(7)
client.set("db_test", "seven")
result = client.get("db_test")
client.close
result
#=> "seven"

## isolated_dbclient with String URI argument
client = Familia.isolated_dbclient("redis://localhost:2525/8")
client.set("uri_test", "eight")
result = client.get("uri_test")
client.close
result
#=> "eight"

## isolated_dbclient with nil uses default
default_db = Familia.uri.db || 0
client = Familia.isolated_dbclient(nil)
client.set("default_test", "default_value")

# Verify it's in the expected database
verification = Familia.with_isolated_dbclient(default_db) do |verify_client|
  verify_client.get("default_test")
end

client.close
verification
#=> "default_value"
