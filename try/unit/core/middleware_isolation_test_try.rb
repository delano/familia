# try/unit/core/middleware_isolation_test_try.rb
#
# Systematic isolation test to find EXACTLY what breaks middleware registration
#
# Strategy: Start minimal and progressively add parts of test_helpers.rb

require_relative '../../../lib/familia'

# Test A: Baseline - middleware only (no test_helpers)
Familia.connection_provider = nil
Familia.enable_database_logging = true
Familia.uri = 'redis://127.0.0.1:2525'
Familia.reconnect!
DatabaseLogger.clear_commands

## Test A: Middleware works without test_helpers
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_a = DatabaseLogger.capture_commands do
  dbclient.set("test_a", "value_a")
end
@commands_a.size
#=> 1

# Test B: Add one simple Horreum class definition
class SimpleClass < Familia::Horreum
  field :name
end

Familia.reconnect!
DatabaseLogger.clear_commands

## Test B: Middleware works after defining simple class
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_b = DatabaseLogger.capture_commands do
  dbclient.set("test_b", "value_b")
end
@commands_b.size
#=> 1

# Test C: Add class with related fields
class ClassWithRelatedFields < Familia::Horreum
  identifier_field :token
  field :token
  field :name
  list :owners
  set :tags
end

Familia.reconnect!
DatabaseLogger.clear_commands

## Test C: Middleware works after defining class with related fields
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_c = DatabaseLogger.capture_commands do
  dbclient.set("test_c", "value_c")
end
@commands_c.size
#=> 1

# Test D: Create instance of simple class
@simple = SimpleClass.new(name: "test")

Familia.reconnect!
DatabaseLogger.clear_commands

## Test D: Middleware works after creating simple instance
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_d = DatabaseLogger.capture_commands do
  dbclient.set("test_d", "value_d")
end
@commands_d.size
#=> 1

# Test E: Create instance of class with related fields
@complex = ClassWithRelatedFields.new(token: "abc123", name: "test")

Familia.reconnect!
DatabaseLogger.clear_commands

## Test E: Middleware works after creating complex instance
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_e = DatabaseLogger.capture_commands do
  dbclient.set("test_e", "value_e")
end
@commands_e.size
#=> 1

# Test F: Create instance with logical_database setting
class ClassWithLogicalDB < Familia::Horreum
  logical_database 2
  identifier_field :id
  field :id
  field :name
end

@logical_db_obj = ClassWithLogicalDB.new(id: "test123", name: "test")

Familia.reconnect!
DatabaseLogger.clear_commands

## Test F: Middleware works after creating instance with logical_database
DatabaseLogger.clear_commands
dbclient = Familia.dbclient
@commands_f = DatabaseLogger.capture_commands do
  dbclient.set("test_f", "value_f")
end
@commands_f.size
#=> 1

# Teardown
DatabaseLogger.clear_commands
