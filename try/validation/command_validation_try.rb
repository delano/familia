# try/validation/command_validation_try.rb

require_relative '../helpers/test_helpers'
require_relative '../../lib/familia/validation'

# Test class for validation testing
class ValidationTestModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :email
  field :active
end

extend Familia::Validation::TestHelpers

# Setup validation test environment
setup_validation_test

## Command recorder captures basic Redis commands
CommandRecorder.start_recording
ValidationTestModel.new(id: "test1", name: "John").save
commands = CommandRecorder.stop_recording
commands.command_count > 0
#=> true

## Command recorder captures command details
CommandRecorder.start_recording
Familia.dbclient.hset("test:key", "field", "value")
commands = CommandRecorder.stop_recording
first_command = commands.commands.first
[first_command.command, first_command.args]
#=> ["HSET", ["test:key", "field", "value"]]

## Expectation DSL allows chaining commands
expectations = CommandExpectations.new
expectations.hset("user:123", "name", "John")
           .hset("user:123", "email", "john@example.com")
           .incr("counter")
expectations.expected_commands.length
#=> 3

## Basic command validation passes with exact match
validator = Validator.new
result = validator.validate do |expect|
  expect.hset("validationtestmodel:test2:object", "name", "Jane")
        .hset("validationtestmodel:test2:object", "id", "test2")

  # Execute the actual operation
  model = ValidationTestModel.new(id: "test2", name: "Jane")
  model.save
end
result.valid?
#=> true

## Command validation fails with wrong command
validator = Validator.new
result = validator.validate do |expect|
  expect.get("wrong:key")  # This won't match actual operation

  ValidationTestModel.new(id: "test3", name: "Bob").save
end
result.valid?
#=> false

## Command validation provides detailed error messages
validator = Validator.new
result = validator.validate do |expect|
  expect.hset("wrong:key", "field", "value")

  ValidationTestModel.new(id: "test4").save
end
result.error_messages.length > 0
#=> true

## Pattern matching works for flexible validation
validator = Validator.new
result = validator.validate do |expect|
  expect.match_pattern(/^HSET validationtestmodel:test5:object/)

  ValidationTestModel.new(id: "test5", name: "Alice").save
end
result.valid?
#=> true

## Any value matchers work correctly
validator = Validator.new
result = validator.validate do |expect|
  expect.hset("validationtestmodel:test6:object", "name", any_string)
        .hset("validationtestmodel:test6:object", "id", "test6")

  ValidationTestModel.new(id: "test6", name: "Charlie").save
end
result.valid?
#=> true

## Test helper assert_redis_commands works
model = ValidationTestModel.new(id: "test7", name: "Dave")
assert_redis_commands do |expect|
  expect.hset("validationtestmodel:test7:object", "name", "Dave")
        .hset("validationtestmodel:test7:object", "id", "test7")

  model.save
end
#=> true

## Test helper assert_command_count works
result = assert_command_count(2) do
  Familia.dbclient.hset("test:count", "field1", "value1")
  Familia.dbclient.hset("test:count", "field2", "value2")
end
result
#=> true

## Test helper assert_no_redis_commands works
result = assert_no_redis_commands do
  # Just create object, don't save
  ValidationTestModel.new(id: "test8", name: "Eve")
end
result
#=> true

## Flexible order validation works
validator = Validator.new
result = validator.validate do |expect|
  expect.strict_order(false)
        .hset("validationtestmodel:test9:object", "name", any_string)
        .hset("validationtestmodel:test9:object", "id", "test9")

  # Save in any order should work
  model = ValidationTestModel.new(id: "test9", name: "Frank")
  model.save
end
result.valid?
#=> true

## Command sequence provides useful metadata
CommandRecorder.start_recording
ValidationTestModel.new(id: "test10", name: "Grace").save
commands = CommandRecorder.stop_recording
summary = {
  command_count: commands.command_count,
  has_commands: commands.commands.any?,
  first_command_type: commands.commands.first&.command_type
}
summary[:command_count] > 0 && summary[:has_commands]
#=> true

## Performance tracking captures timing information
validator = Validator.new(performance_tracking: true)
result = validator.validate do |expect|
  expect.match_pattern(/HSET/)

  ValidationTestModel.new(id: "test11", name: "Henry").save
end
result.respond_to?(:performance_metrics) && result.performance_metrics[:total_commands] > 0
#=> true

## Validation result provides comprehensive summary
validator = Validator.new
result = validator.validate do |expect|
  expect.hset("validationtestmodel:test12:object", "name", "Iris")

  ValidationTestModel.new(id: "test12", name: "Iris").save
end
summary = result.summary
summary[:valid] == true && summary[:expected_commands] == 1
#=> true

## Complex validation with multiple operations
class ComplexTestModel < Familia::Horreum
  identifier_field :id
  field :id, :name, :email
  list :tags
  set :categories
end

validator = Validator.new
result = validator.validate do |expect|
  expect.hset("complextestmodel:complex1:object", "name", "Complex")
        .hset("complextestmodel:complex1:object", "id", "complex1")
        .lpush("complextestmodel:complex1:tags", "tag1")
        .sadd("complextestmodel:complex1:categories", "cat1")

  model = ComplexTestModel.new(id: "complex1", name: "Complex")
  model.save
  model.tags.lpush("tag1")
  model.categories.sadd("cat1")
end
result.valid?
#=> true

# Cleanup
teardown_validation_test

# Clean up test data
test_keys = Familia.dbclient.keys("validationtestmodel:*")
test_keys.concat(Familia.dbclient.keys("complextestmodel:*"))
test_keys.concat(Familia.dbclient.keys("test:*"))
Familia.dbclient.del(*test_keys) if test_keys.any?
