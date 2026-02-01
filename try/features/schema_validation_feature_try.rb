# try/features/schema_validation_feature_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require 'json'
require 'tmpdir'
require 'fileutils'

Familia.debug = false

# Store original config for teardown
@original_schema_path = Familia.schema_path
@original_schemas = Familia.schemas
@original_validator = Familia.schema_validator

# Setup - create temp schema directory and configure before defining classes
@schema_dir = Dir.mktmpdir('familia_schema_feature')
@prefix = "familia:test:schemafeature:#{Process.pid}"

# Create test schema for SchemaValidatedModel class
# Note: snake_case filename converts to CamelCase class name
# Using type arrays to allow null for optional fields (age is not required)
File.write(File.join(@schema_dir, 'schema_validated_model.json'), JSON.generate({
  'type' => 'object',
  'properties' => {
    'email' => { 'type' => 'string', 'format' => 'email' },
    'name' => { 'type' => 'string', 'minLength' => 1 },
    'age' => { 'type' => ['integer', 'null'], 'minimum' => 0, 'maximum' => 150 }
  },
  'required' => ['email', 'name']
}))

Familia.schema_path = @schema_dir
Familia.schema_validator = :json_schemer
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!

# Define test model with schema validation feature dynamically
# Uses Object.const_set to define at runtime after schema is loaded
Object.const_set(:SchemaValidatedModel, Class.new(Familia::Horreum) do
  feature :schema_validation

  identifier_field :modelid
  field :modelid
  field :email
  field :name
  field :age
end)

# Define model without schema validation feature for comparison
Object.const_set(:NoSchemaFeatureModel, Class.new(Familia::Horreum) do
  identifier_field :id
  field :id
  field :data
end) unless defined?(NoSchemaFeatureModel)

# Define model with feature but no schema file
Object.const_set(:UnschemaedFeatureModel, Class.new(Familia::Horreum) do
  feature :schema_validation

  identifier_field :uid
  field :uid
  field :stuff
end)

## Model class has schema class method
SchemaValidatedModel.respond_to?(:schema)
#=> true

## Model class schema returns Hash
SchemaValidatedModel.schema.is_a?(Hash)
#=> true

## Model class has schema_defined? method
SchemaValidatedModel.respond_to?(:schema_defined?)
#=> true

## Model class schema_defined? returns true when schema exists
SchemaValidatedModel.schema_defined?
#=> true

## Instance can access schema via instance method
instance = SchemaValidatedModel.new(modelid: 't1', email: 'test@example.com', name: 'Test')
instance.respond_to?(:schema)
#=> true

## Instance schema returns same Hash as class schema
instance = SchemaValidatedModel.new(modelid: 't1', email: 'test@example.com', name: 'Test')
instance.schema == SchemaValidatedModel.schema
#=> true

## valid_against_schema? returns true for valid data
instance = SchemaValidatedModel.new(modelid: 't2', email: 'test@example.com', name: 'Test', age: 25)
instance.valid_against_schema?
#=> true

## valid_against_schema? returns false for invalid email format
instance = SchemaValidatedModel.new(modelid: 't3', email: 'not-an-email', name: 'Test')
instance.valid_against_schema?
#=> false

## valid_against_schema? returns false for missing required name field
instance = SchemaValidatedModel.new(modelid: 't4', email: 'test@example.com')
instance.valid_against_schema?
#=> false

## valid_against_schema? returns false for age out of range
instance = SchemaValidatedModel.new(modelid: 't5', email: 'test@example.com', name: 'Test', age: 200)
instance.valid_against_schema?
#=> false

## schema_validation_errors returns empty array for valid data
instance = SchemaValidatedModel.new(modelid: 't6', email: 'test@example.com', name: 'Valid')
instance.schema_validation_errors.empty?
#=> true

## schema_validation_errors returns non-empty array for invalid data
instance = SchemaValidatedModel.new(modelid: 't7', email: 'not-valid', name: 'Test')
instance.schema_validation_errors.size > 0
#=> true

## schema_validation_errors returns array type
instance = SchemaValidatedModel.new(modelid: 't8', email: 'test@example.com', name: '')
errors = instance.schema_validation_errors
errors.is_a?(Array)
#=> true

## validate_against_schema! returns true for valid data
instance = SchemaValidatedModel.new(modelid: 't9', email: 'valid@example.com', name: 'Valid')
instance.validate_against_schema!
#=> true

## validate_against_schema! raises SchemaValidationError for invalid email
instance = SchemaValidatedModel.new(modelid: 't10', email: 'bad-email', name: 'Test')
begin
  instance.validate_against_schema!
  false
rescue Familia::SchemaValidationError
  true
end
#=> true

## validate_against_schema! raises SchemaValidationError for missing required field
instance = SchemaValidatedModel.new(modelid: 't11', email: 'test@example.com')
begin
  instance.validate_against_schema!
  false
rescue Familia::SchemaValidationError
  true
end
#=> true

## SchemaValidationError includes errors accessor
instance = SchemaValidatedModel.new(modelid: 't12', email: 'bad')
begin
  instance.validate_against_schema!
  nil
rescue Familia::SchemaValidationError => e
  e.respond_to?(:errors) && e.errors.is_a?(Array) && e.errors.size > 0
end
#=> true

## Model without feature does not have valid_against_schema? method
instance = NoSchemaFeatureModel.new(id: 'x', data: 'anything')
instance.respond_to?(:valid_against_schema?)
#=> false

## Model without feature does not have validate_against_schema! method
instance = NoSchemaFeatureModel.new(id: 'x', data: 'anything')
instance.respond_to?(:validate_against_schema!)
#=> false

## Model without feature does not have schema_validation_errors method
instance = NoSchemaFeatureModel.new(id: 'x', data: 'anything')
instance.respond_to?(:schema_validation_errors)
#=> false

## Model with feature but no schema file still works - valid_against_schema returns true
instance = UnschemaedFeatureModel.new(uid: 'u1', stuff: 'whatever')
instance.valid_against_schema?
#=> true

## Model with feature but no schema file - schema_validation_errors returns empty array
instance = UnschemaedFeatureModel.new(uid: 'u2', stuff: 123)
instance.schema_validation_errors
#=> []

## Model with feature but no schema file - validate_against_schema! returns true
instance = UnschemaedFeatureModel.new(uid: 'u3', stuff: nil)
instance.validate_against_schema!
#=> true

## Model with feature but no schema - schema_defined? returns false
UnschemaedFeatureModel.schema_defined?
#=> false

## Model with feature but no schema - schema returns nil
UnschemaedFeatureModel.schema.nil?
#=> true

## Feature is properly registered in enabled features
SchemaValidatedModel.features_enabled.include?(:schema_validation)
#=> true

## schema_validation feature is available in Familia
Familia::Base.features_available.key?(:schema_validation)
#=> true

# Teardown
FileUtils.rm_rf(@schema_dir)
Familia.schema_path = @original_schema_path
Familia.schemas = @original_schemas || {}
Familia.schema_validator = @original_validator || :json_schemer
Familia::SchemaRegistry.reset!
Object.send(:remove_const, :SchemaValidatedModel) if defined?(SchemaValidatedModel)
Object.send(:remove_const, :NoSchemaFeatureModel) if defined?(NoSchemaFeatureModel)
Object.send(:remove_const, :UnschemaedFeatureModel) if defined?(UnschemaedFeatureModel)
