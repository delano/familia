# try/migration/schema_validation_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'
require 'json'
require 'tmpdir'
require 'fileutils'

Familia.debug = false

# Setup
@schema_dir = Dir.mktmpdir('familia_migration_schemas')

# Store and configure
@original_schema_path = Familia.schema_path
@original_schemas = Familia.schemas
@original_validator = Familia.schema_validator
@initial_migrations = Familia::Migration.migrations.dup

# Test model - define at top level to avoid Tryouts class scoping issue
# The class will have a simple name 'MigrationSchemaModel' instead of
# '#<Class:0x...>::MigrationSchemaModel' which happens when defined inside
# Tryouts' evaluation context
Object.const_set(:MigrationSchemaModel, Class.new(Familia::Horreum) do
  feature :schema_validation
  identifier_field :custid
  field :custid
  field :email
  field :status
end) unless defined?(::MigrationSchemaModel)

# Custom migration for testing validation hooks
Object.const_set(:TestValidationMigration, Class.new(Familia::Migration::Model) do
  self.migration_id = 'test_validation_hooks'

  define_method(:validate_before_transform?) { true }
  define_method(:validate_after_transform?) { true }
  define_method(:migration_needed?) { false }
  define_method(:prepare) { @model_class = MigrationSchemaModel }
  define_method(:process_record) { |obj, key| }
end) unless defined?(::TestValidationMigration)

# Create test schema after class is defined so we can use the actual name
File.write(File.join(@schema_dir, 'migration_schema_model.json'), JSON.generate({
  type: 'object',
  properties: {
    email: { type: 'string', format: 'email' },
    status: { type: 'string', enum: ['active', 'inactive', 'pending'] }
  },
  required: ['email']
}))

Familia.schema_path = @schema_dir
Familia.schema_validator = :json_schemer
Familia::SchemaRegistry.reset!
Familia::SchemaRegistry.load!

## Base migration has validate_schema method
migration = Familia::Migration::Base.new
migration.respond_to?(:validate_schema)
#=> true

## Base migration has validate_schema! method
migration = Familia::Migration::Base.new
migration.respond_to?(:validate_schema!)
#=> true

## validate_schema returns valid result for conforming data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c1', email: 'test@example.com', status: 'active')
result = migration.validate_schema(obj)
result[:valid]
#=> true

## validate_schema returns errors for non-conforming data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c2', email: 'invalid-email', status: 'unknown')
result = migration.validate_schema(obj)
result[:valid]
#=> false

## validate_schema errors array has content for invalid data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c3', email: 'bad')
result = migration.validate_schema(obj)
result[:errors].size > 0
#=> true

## validate_schema! raises for invalid data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c4', status: 'active')
begin
  migration.validate_schema!(obj)
  false
rescue Familia::SchemaValidationError
  true
end
#=> true

## validate_schema! returns true for valid data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c5', email: 'valid@example.com', status: 'pending')
migration.validate_schema!(obj)
#=> true

## schema_validation_enabled? returns true by default
migration = Familia::Migration::Base.new
migration.schema_validation_enabled?
#=> true

## skip_schema_validation! disables validation
migration = Familia::Migration::Base.new
migration.skip_schema_validation!
migration.schema_validation_enabled?
#=> false

## validate_schema returns valid when validation disabled
migration = Familia::Migration::Base.new
migration.skip_schema_validation!
obj = MigrationSchemaModel.new(custid: 'c6', email: 'invalid')
result = migration.validate_schema(obj)
result[:valid]
#=> true

## Model migration has validate_before_transform? protected method
migration = Familia::Migration::Model.new
migration.respond_to?(:validate_before_transform?, true)
#=> true

## Model migration has validate_after_transform? protected method
migration = Familia::Migration::Model.new
migration.respond_to?(:validate_after_transform?, true)
#=> true

## validate_before_transform? defaults to false via send
migration = Familia::Migration::Model.new
migration.send(:validate_before_transform?)
#=> false

## validate_after_transform? defaults to false via send
migration = Familia::Migration::Model.new
migration.send(:validate_after_transform?)
#=> false

## Custom migration has before validation hook enabled
migration = TestValidationMigration.new
migration.send(:validate_before_transform?)
#=> true

## Custom migration has after validation hook enabled
migration = TestValidationMigration.new
migration.send(:validate_after_transform?)
#=> true

## process_record_with_validation is a protected method
migration = TestValidationMigration.new
migration.respond_to?(:process_record_with_validation, true)
#=> true

## validate_schema with context returns valid for good data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c7', email: 'valid@example.com', status: 'active')
result = migration.validate_schema(obj, context: 'before transform')
result[:valid]
#=> true

## validate_schema! with context raises for invalid data
migration = Familia::Migration::Base.new
obj = MigrationSchemaModel.new(custid: 'c8', status: 'active')
begin
  migration.validate_schema!(obj, context: 'after transform')
  false
rescue Familia::SchemaValidationError
  true
end
#=> true

## Model migration inherits schema validation from Base
Familia::Migration::Model.ancestors.include?(Familia::Migration::Base)
#=> true

## Model migration responds to all schema validation methods
migration = Familia::Migration::Model.new
[:validate_schema, :validate_schema!, :schema_validation_enabled?, :skip_schema_validation!].all? do |m|
  migration.respond_to?(m)
end
#=> true

# Teardown
FileUtils.rm_rf(@schema_dir)
Familia.schema_path = @original_schema_path
Familia.schemas = @original_schemas || {}
Familia.schema_validator = @original_validator || :json_schemer
Familia::SchemaRegistry.reset!
Familia::Migration.migrations.replace(@initial_migrations)
Familia::Migration.migrations.delete(TestValidationMigration) if defined?(::TestValidationMigration)
# Clean up the top-level constants
Object.send(:remove_const, :MigrationSchemaModel) if defined?(::MigrationSchemaModel)
Object.send(:remove_const, :TestValidationMigration) if defined?(::TestValidationMigration)
