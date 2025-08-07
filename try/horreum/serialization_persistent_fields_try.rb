# try/horreum/serialization_persistent_fields_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test class with mixed field categories for serialization
class SerializationCategoryTest < Familia::Horreum
  identifier_field :id
  field :id
  field :name                           # persistent by default
  field :email, category: :encrypted    # persistent, encrypted category
  field :cache_data, category: :transient # should be excluded from serialization
  field :description, category: :persistent # explicitly persistent
  field :temp_settings, category: :transient # should be excluded
  field :metadata, category: :persistent # explicitly persistent
end

# Class with all transient fields
class AllTransientSerializationTest < Familia::Horreum
  identifier_field :id
  field :id
  field :temp1, category: :transient
  field :temp2, category: :transient
end

# Mixed categories with aliased fields
class AliasedSerializationTest < Familia::Horreum
  identifier_field :id
  field :id
  field :internal_name, as: :display_name, category: :persistent
  field :temp_cache, as: :cache, category: :transient
  field :user_data, as: :data, category: :encrypted
end

# Setup test instance with all field types
@serialization_test = SerializationCategoryTest.new(
  id: 'serialize_test_1',
  name: 'Test User',
  email: 'test@example.com',
  cache_data: 'temporary_cache_value',
  description: 'A test user description',
  temp_settings: { theme: 'dark', cache: true },
  metadata: { version: 1, last_login: '2025-01-01' }
)

@all_transient = AllTransientSerializationTest.new(
  id: 'transient_test_1',
  temp1: 'value1',
  temp2: 'value2'
)

@aliased_test = AliasedSerializationTest.new(
  id: 'aliased_test_1',
  display_name: 'Display Name',
  cache: 'cache_value',
  data: { key: 'value' }
)

## to_h excludes transient fields
@hash_result = @serialization_test.to_h
@hash_result.keys.sort
#=> [:description, :email, :id, :metadata, :name]

## to_h includes all persistent fields
@hash_result.key?(:name)
#=> true

## to_h includes encrypted persistent fields
@hash_result.key?(:email)
#=> true

## to_h includes explicitly persistent fields
@hash_result.key?(:description)
#=> true

## to_h excludes transient fields from serialization
@hash_result.key?(:cache_data)
#=> false

## to_h excludes all transient fields
@hash_result.key?(:temp_settings)
#=> false

## to_h serializes complex values correctly
@hash_result[:metadata]
#=:> String

## to_a excludes transient fields
@array_result = @serialization_test.to_a
@array_result.size
#=> 5

## to_a maintains field order for persistent fields only
SerializationCategoryTest.persistent_fields
#=> [:id, :name, :email, :description, :metadata]

## Save operation only persists persistent fields
@serialization_test.save
#=> true

## Refresh loads only persistent fields
@serialization_test.refresh!
@serialization_test.name
#=> "Test User"

## Transient field values are not persisted in redis
@serialization_test.cache_data
#=> "temporary_cache_value"

## When refreshed, transient fields retain their in-memory values
@serialization_test.refresh!
@serialization_test.cache_data  # Should still be in memory but not from redis
#=> "temporary_cache_value"

## Field definitions are preserved during serialization
SerializationCategoryTest.field_definitions[:cache_data].category
#=> :transient

## Persistent fields filtering works correctly
SerializationCategoryTest.persistent_fields.include?(:cache_data)
#=> false

## All persistent fields are included in persistent_fields
SerializationCategoryTest.persistent_fields.include?(:email)
#=> true

## to_h with only id field when all others are transient
@all_transient.to_h
#=> { id: "transient_test_1" }

## to_a with only id field when all others are transient
@all_transient.to_a
#=> ["transient_test_1"]

## Aliased fields serialization uses original field names
@aliased_hash = @aliased_test.to_h
@aliased_hash.keys.sort
#=> [:id, :internal_name, :user_data]

## Aliased transient fields are excluded
@aliased_hash.key?(:temp_cache)
#=> false

## Serialization works with accessor methods through aliases
@aliased_test.display_name = 'Updated Name'
@aliased_test.to_h[:internal_name]
#=> "Updated Name"

## Clear fields respects field method map
@serialization_test.clear_fields!
@serialization_test.name
#=> nil

## Clear fields affects aliased methods correctly
@aliased_test.clear_fields!
@aliased_test.display_name
#=> nil

@serialization_test.destroy! rescue nil
@all_transient.destroy! rescue nil
@aliased_test.destroy! rescue nil
@serialization_test = nil
@all_transient = nil
@aliased_test = nil
