# try/horreum/field_categories_try.rb

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Define test class with various field types
class FieldCategoryTest < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :id
  field :id
  field :name                           # regular field
  encrypted_field :email                # encrypted field
  transient_field :tryouts_cache_data   # transient field
  field :description                    # regular persistent field
  field :settings                       # regular field
end

# Test class with multiple transient fields
class MultiTransientTest < Familia::Horreum
  feature :transient_fields

  identifier_field :id
  field :id
  field :permanent_data
  transient_field :temp1
  transient_field :temp2
  transient_field :temp3
end

# Field types work with field aliasing
class AliasedCategoryTest < Familia::Horreum
  feature :transient_fields

  identifier_field :id
  field :id
  transient_field :internal_temp, as: :temp
  field :internal_perm, as: :perm
end

# Test edge case with all transient fields
class AllTransientTest < Familia::Horreum
  feature :transient_fields

  identifier_field :id
  field :id
  transient_field :temp1
  transient_field :temp2
end

## Field types are stored correctly
@test_obj = FieldCategoryTest.new(id: 'test123')
FieldCategoryTest.field_types.size
#=> 6

## Default category field has correct category
FieldCategoryTest.field_types[:name].category
#=> :field

## Encrypted category field has correct category
FieldCategoryTest.field_types[:email].category
#=> :encrypted

## Transient category field has correct category
FieldCategoryTest.field_types[:tryouts_cache_data].category
#=> :transient

## Regular fields have :field category
FieldCategoryTest.field_types[:description].category
#=> :field

## Regular fields default to :field category
FieldCategoryTest.field_types[:settings].category
#=> :field

## persistent_fields excludes transient fields
FieldCategoryTest.persistent_fields
#=> [:id, :name, :email, :description, :settings]

## persistent_fields includes encrypted and persistent fields
FieldCategoryTest.persistent_fields.include?(:email)
#=> true

## persistent_fields includes default category fields
FieldCategoryTest.persistent_fields.include?(:name)
#=> true

## persistent_fields excludes transient fields
FieldCategoryTest.persistent_fields.include?(:tryouts_cache_data)
#=> false

## Field definitions map provides backward compatibility
FieldCategoryTest.field_method_map[:name]
#=> :name

## Field definitions map works for all fields
FieldCategoryTest.field_method_map[:email]
#=> :email

## Multiple transient fields are handled correctly
MultiTransientTest.persistent_fields
#=> [:id, :permanent_data]

## Aliased transient field is excluded from persistent_fields
AliasedCategoryTest.persistent_fields.include?(:internal_temp)
#=> false

## Aliased persistent field is included in persistent_fields
AliasedCategoryTest.persistent_fields.include?(:internal_perm)
#=> true

## Field type stores original field name, not alias
AliasedCategoryTest.field_types[:internal_temp].name
#=> :internal_temp

## Field type stores alias as method name
AliasedCategoryTest.field_types[:internal_temp].method_name
#=> :temp

## persistent_fields with mostly transient fields
AllTransientTest.persistent_fields
#=> [:id]

@test_obj.destroy! rescue nil
@test_obj = nil
