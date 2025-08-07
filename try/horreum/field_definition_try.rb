# try/horreum/field_definition_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Setup a test field definition
@field_def = Familia::FieldDefinition.new(
  field_name: :email,
  method_name: :email,
  fast_method_name: :email!,
  on_conflict: :raise,
  category: :encrypted
)

## FieldDefinition holds field name correctly
@field_def.field_name
#=> :email

## FieldDefinition holds method name correctly
@field_def.method_name
#=> :email

## FieldDefinition holds fast method name correctly
@field_def.fast_method_name
#=> :email!

## FieldDefinition holds conflict strategy correctly
@field_def.on_conflict
#=> :raise

## FieldDefinition holds category correctly
@field_def.category
#=> :encrypted

## FieldDefinition returns generated methods list
@field_def.generated_methods
#=> [:email, :email!]

## FieldDefinition with nil category defaults to :field
@basic_field = Familia::FieldDefinition.new(
  field_name: :name,
  method_name: :name,
  fast_method_name: :name!,
  on_conflict: :skip,
  category: nil
)
@basic_field.category
#=> :field

## FieldDefinition persistent? returns true for non-transient fields
@field_def.persistent?
#=> true

## FieldDefinition persistent? returns false for transient fields
@transient_field = Familia::FieldDefinition.new(
  field_name: :temp_data,
  method_name: :temp_data,
  fast_method_name: :temp_data!,
  on_conflict: :raise,
  category: :transient
)
@transient_field.persistent?
#=> false

## FieldDefinition to_s includes all attributes
@field_def.to_s
#=~>/#<Familia::FieldDefinition field_name=email method_name=email fast_method_name=email! on_conflict=raise category=encrypted>/

## FieldDefinition inspect is same as to_s
@field_def.inspect
#=~>/#<Familia::FieldDefinition field_name=email method_name=email fast_method_name=email! on_conflict=raise category=encrypted>/

@field_def = nil
@basic_field = nil
@transient_field = nil
