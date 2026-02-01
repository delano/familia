# try/features/schema_registry_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require 'json'
require 'tmpdir'
require 'fileutils'

Familia.debug = false

# Setup - create temp schema directory
@schema_dir = Dir.mktmpdir('familia_schemas')

# Create test schema files
File.write(File.join(@schema_dir, 'customer.json'), JSON.generate({
  type: 'object',
  properties: {
    email: { type: 'string', format: 'email' },
    age: { type: 'integer', minimum: 0 }
  },
  required: ['email']
}))

File.write(File.join(@schema_dir, 'user_session.json'), JSON.generate({
  type: 'object',
  properties: {
    token: { type: 'string', minLength: 32 }
  }
}))

# Store original settings
@original_schema_path = Familia.schema_path
@original_schemas = Familia.schemas
@original_validator = Familia.schema_validator

# Ensure json_schemer is used for validation
Familia.schema_validator = :json_schemer

## SchemaRegistry class exists
Familia::SchemaRegistry.is_a?(Class)
#=> true

## SchemaRegistry starts unloaded after reset
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.loaded?
#=> false

## schema_for returns nil before loading when no config
Familia::SchemaRegistry.reset!
Familia.schema_path = nil
Familia.schemas = {}
result = Familia::SchemaRegistry.schema_for('Customer')
result.nil?
#=> true

## load! loads schemas from schema_path
Familia.schema_path = @schema_dir
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
Familia::SchemaRegistry.loaded?
#=> true

## schema_for returns parsed schema after loading
Familia.schema_path = @schema_dir
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
schema = Familia::SchemaRegistry.schema_for('Customer')
schema['type']
#=> 'object'

## schema_defined? returns true for loaded schemas
Familia.schema_path = @schema_dir
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
Familia::SchemaRegistry.schema_defined?('Customer')
#=> true

## schema_defined? returns false for unknown schemas
Familia::SchemaRegistry.schema_defined?('NonExistent')
#=> false

## Underscore filenames convert to CamelCase class names
Familia.schema_path = @schema_dir
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
Familia::SchemaRegistry.schema_defined?('UserSession')
#=> true

## validate returns valid for conforming data
Familia.schema_path = @schema_dir
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
result = Familia::SchemaRegistry.validate('Customer', { 'email' => 'test@example.com', 'age' => 25 })
result[:valid]
#=> true

## validate returns errors for missing required field
result = Familia::SchemaRegistry.validate('Customer', { 'age' => 25 })
result[:valid]
#=> false

## validate errors array is non-empty for invalid data
result = Familia::SchemaRegistry.validate('Customer', { 'age' => 25 })
result[:errors].size > 0
#=> true

## validate returns valid for undefined schemas (no-op)
result = Familia::SchemaRegistry.validate('NonExistent', { 'anything' => 'goes' })
result[:valid]
#=> true

## validate! raises SchemaValidationError for invalid data
begin
  Familia::SchemaRegistry.validate!('Customer', { 'age' => 'not a number' })
  false
rescue Familia::SchemaValidationError => e
  e.errors.size > 0
end
#=> true

## validate! returns true for valid data
result = Familia::SchemaRegistry.validate!('Customer', { 'email' => 'valid@example.com' })
result
#=> true

## Explicit schemas hash loads correctly
Familia.schema_path = nil
Familia.schemas = { 'ExplicitModel' => File.join(@schema_dir, 'customer.json') }
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
Familia::SchemaRegistry.schema_defined?('ExplicitModel')
#=> true

## schemas returns copy of all loaded schemas
Familia.schema_path = @schema_dir
Familia.schemas = {}
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
schemas = Familia::SchemaRegistry.schemas
schemas.keys.sort
#=> ['Customer', 'UserSession']

## reset! clears loaded state
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.loaded?
#=> false

## SchemaValidationError has errors accessor
begin
  Familia.schema_path = @schema_dir
  Familia::SchemaRegistry.reset!
  Familia::SchemaRegistry.load!
  Familia::SchemaRegistry.validate!('Customer', {})
rescue Familia::SchemaValidationError => e
  e.respond_to?(:errors) && e.errors.is_a?(Array)
end
#=> true

## load! is idempotent - calling multiple times does not reload
Familia.schema_path = @schema_dir
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
first_schema = Familia::SchemaRegistry.schema_for('Customer')
Familia::SchemaRegistry.load!
second_schema = Familia::SchemaRegistry.schema_for('Customer')
first_schema.equal?(second_schema)
#=> true

## schema_for auto-loads when not yet loaded
Familia.schema_path = @schema_dir
Familia.schemas = {}
Familia::SchemaRegistry.reset!
schema = Familia::SchemaRegistry.schema_for('Customer')
schema['type']
#=> 'object'

## NullValidator always returns valid when validation disabled
Familia.schema_path = @schema_dir
Familia.schema_validator = :none
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!
result = Familia::SchemaRegistry.validate('Customer', {})
Familia.schema_validator = :json_schemer
result[:valid]
#=> true

# Teardown
FileUtils.rm_rf(@schema_dir)
Familia.schema_path = @original_schema_path
Familia.schemas = @original_schemas || {}
Familia.schema_validator = @original_validator || :json_schemer
Familia::SchemaRegistry.reset!
