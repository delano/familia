# try/horreum/field_definition_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Create a custom field type for testing with category support
class TestFieldType < Familia::FieldType
  def initialize(name, category: :field, **kwargs)
    super(name, **kwargs)
    @category = category
  end

  def category
    @category || :field
  end

  def persistent?
    category != :transient
  end
end

# Setup a test field type (replacing the old FieldDefinition)
@field_type = TestFieldType.new(
  :email,
  as: :email,
  fast_method: :email!,
  on_conflict: :raise,
  category: :encrypted
)

## FieldType holds field name correctly
@field_type.name
#=> :email

## FieldType holds method name correctly
@field_type.method_name
#=> :email

## FieldType holds fast method name correctly
@field_type.fast_method_name
#=> :email!

## FieldType holds conflict strategy correctly
@field_type.on_conflict
#=> :raise

## FieldType holds category correctly
@field_type.category
#=> :encrypted

## FieldType returns generated methods list
@field_type.generated_methods
#=> [:email, :email!]

## FieldType with nil category defaults to :field
@basic_field = TestFieldType.new(
  :name,
  as: :name,
  fast_method: :name!,
  on_conflict: :skip,
  category: nil
)
@basic_field.category
#=> :field

## FieldType persistent? returns true for non-transient fields
@field_type.persistent?
#=> true

## FieldType persistent? returns false for transient fields
@transient_field = TestFieldType.new(
  :temp_data,
  as: :temp_data,
  fast_method: :temp_data!,
  on_conflict: :raise,
  category: :transient
)
@transient_field.persistent?
#=> false

## FieldType to_s includes all attributes
@field_type.to_s
#=~>/#<.*TestFieldType name=email method_name=email fast_method_name=email! on_conflict=raise category=encrypted>/

## FieldType inspect is same as to_s
@field_type.inspect
#=~>/#<.*TestFieldType name=email method_name=email fast_method_name=email! on_conflict=raise category=encrypted>/

@field_type = nil
@basic_field = nil
@transient_field = nil
