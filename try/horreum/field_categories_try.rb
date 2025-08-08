# try/horreum/field_categories_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

# Define test class with various field categories
class FieldCategoryTest < Familia::Horreum
  identifier_field :id
  field :id
  field :name                           # default category (:field)
  field :email, category: :encrypted    # encrypted category
  field :tryouts_cache_data, category: :transient # transient category
  field :description, category: :persistent # explicit persistent category
  field :settings, category: nil        # nil category (defaults to :field)
end

# Test class with multiple transient fields
class MultiTransientTest < Familia::Horreum
  identifier_field :id
  field :id
  field :permanent_data
  field :temp1, category: :transient
  field :temp2, category: :transient
  field :temp3, category: :transient
end

# Field categories work with field aliasing
class AliasedCategoryTest < Familia::Horreum
  identifier_field :id
  field :id
  field :internal_temp, as: :temp, category: :transient
  field :internal_perm, as: :perm, category: :persistent
end

# Test edge case with all transient fields
class AllTransientTest < Familia::Horreum
  identifier_field :id
  field :id
  field :temp1, category: :transient
  field :temp2, category: :transient
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

## Explicit persistent category field has correct category
FieldCategoryTest.field_types[:description].category
#=> :persistent

## Nil category field defaults to :field
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
