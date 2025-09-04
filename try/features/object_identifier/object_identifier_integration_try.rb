# try/features/object_identifier/object_identifier_integration_try.rb

require_relative '../../helpers/test_helpers'

Familia.debug = false

# Integration test for ObjectIdentifier and ExternalIdentifiers features together

# Class using both features with defaults
class IntegrationTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier  # This depends on :object_identifier
  identifier_field :id
  field :id
  field :name
  field :email
end

# Class with custom configurations for both features
class CustomIntegrationTest < Familia::Horreum
  feature :object_identifier, generator: :hex
  feature :external_identifier, prefix: 'custom'
  identifier_field :id
  field :id
  field :name
end

# Class testing full lifecycle with Redis persistence
class PersistenceTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier
  identifier_field :id
  field :id
  field :name
  field :created_at
end

# Setup test objects
@integration_obj = IntegrationTest.new(id: 'integration_1', name: 'Integration Test', email: 'test@example.com')
@custom_obj = CustomIntegrationTest.new(id: 'custom_1', name: 'Custom Test')

## Object identifier feature is automatically included
IntegrationTest.features_enabled.include?(:object_identifier)
#==> true

## External identifier feature is included
IntegrationTest.features_enabled.include?(:external_identifier)
#==> true

## Object responds to objid accessor
obj = IntegrationTest.new
obj.respond_to?(:objid)
#==> true

## Object responds to extid accessor
obj = IntegrationTest.new
obj.respond_to?(:extid)
#==> true

## Class responds to find_by_objid method
IntegrationTest.respond_to?(:find_by_objid)
#==> true

## Class responds to find_by_extid method
IntegrationTest.respond_to?(:find_by_extid)
#==> true

## objid and extid are different values
obj = IntegrationTest.new
obj.objid != obj.extid
#==> true

## extid is deterministically generated from objid for same object
obj = IntegrationTest.new
original_objid = obj.objid
original_extid = obj.extid
# Multiple calls on same object should return same extid
obj.extid == original_extid
#==> true

## Custom objid uses hex format (64 chars for 256-bit)
@custom_obj.objid.match(/\A[0-9a-f]{64}\z/)
#=*> nil

## Custom extid uses custom prefix
@custom_obj.extid.start_with?('custom_')
#==> true

## Both IDs persist through save/load cycle
persistence_obj = PersistenceTest.new
persistence_obj.id = 'persistence_test'
persistence_obj.name = 'Persistence Test Object'
persistence_obj.created_at = Time.now.to_i
original_objid = persistence_obj.objid
original_extid = persistence_obj.extid
persistence_obj.save

# Load from Redis
loaded_obj = PersistenceTest.new(id: 'persistence_test')

## objid persists after save/load
persistence_obj = PersistenceTest.new
persistence_obj.id = 'persistence_test'
persistence_obj.name = 'Persistence Test Object'
persistence_obj.created_at = Time.now.to_i
original_objid = persistence_obj.objid
persistence_obj.save
loaded_obj = PersistenceTest.new(id: 'persistence_test')
loaded_obj.objid == original_objid
#==> true

## extid persists after save/load
persistence_obj = PersistenceTest.new
persistence_obj.id = 'persistence_test'
persistence_obj.name = 'Persistence Test Object'
persistence_obj.created_at = Time.now.to_i
original_extid = persistence_obj.extid
persistence_obj.save
loaded_obj = PersistenceTest.new(id: 'persistence_test')
loaded_obj.extid == original_extid
#==> true

## objid instance variable starts nil (lazy generation)
lazy_obj = IntegrationTest.new
lazy_obj.instance_variable_get(:@objid)
#=> nil

## extid instance variable starts nil (lazy generation)
lazy_obj = IntegrationTest.new
lazy_obj.instance_variable_get(:@extid)
#=> nil

## Accessing objid first doesn't trigger extid generation
lazy_obj = IntegrationTest.new
lazy_obj.objid
lazy_obj.instance_variable_get(:@extid)
#=> nil

## Accessing extid triggers objid generation if needed
lazy_obj2 = IntegrationTest.new
lazy_obj2.extid  # This should trigger objid generation too
lazy_obj2.instance_variable_get(:@objid)
#=*> nil

## Check field types objid
IntegrationTest.field_types[:objid].is_a?(Familia::Features::ObjectIdentifier::ObjectIdentifierFieldType)
#==> true

## ObjectIdentifier fields have correct types in field registry
IntegrationTest.field_types[:objid].class.ancestors.include?(Familia::Features::ObjectIdentifier::ObjectIdentifierFieldType)
#==> true

## ExternalIdentifier fields have correct types in field registry
IntegrationTest.field_types[:extid].class.ancestors.include?(Familia::Features::ExternalIdentifier::ExternalIdentifierFieldType)
#==> true

## Object identifier options are preserved
opts = IntegrationTest.feature_options
opts.key?(:object_identifier)
#==> true

## External identifiersoptions are preserved
opts = IntegrationTest.feature_options
opts.key?(:external_identifier)
#==> true

## Generator default configuration is applied correctly
IntegrationTest.feature_options(:object_identifier)[:generator]
#=> :uuid_v7

## Prefix default configuration is applied correctly
IntegrationTest.feature_options(:external_identifier)[:prefix]
#=> "ext"

## Custom generator configuration is applied correctly
CustomIntegrationTest.feature_options(:object_identifier)[:generator]
#=> :hex

## Custom prefix configuration is applied correctly
CustomIntegrationTest.feature_options(:external_identifier)[:prefix]
#=> "custom"

## objid is URL-safe (UUID format)
obj = IntegrationTest.new
obj.objid.match(/\A[A-Za-z0-9\-]+\z/)
#=*> nil

## extid is URL-safe (base36 format)
obj = IntegrationTest.new
obj.extid.match(/\A[a-z0-9_]+\z/)
#=*> nil

## Data integrity preserved during complex initialization
complex_obj = IntegrationTest.new(
  id: 'complex_integration',
  name: 'Complex Integration',
  email: 'complex@test.com',
  objid: 'preset_objid_123',
  extid: 'preset_ext_456'
)

## Preset objid value is preserved
complex_obj = IntegrationTest.new(
  id: 'complex_integration',
  name: 'Complex Integration',
  email: 'complex@test.com',
  objid: 'preset_objid_123',
  extid: 'preset_ext_456'
)
complex_obj.objid
#=> 'preset_objid_123'

## Preset extid value is preserved
complex_obj = IntegrationTest.new(
  id: 'complex_integration',
  name: 'Complex Integration',
  email: 'complex@test.com',
  objid: 'preset_objid_123',
  extid: 'preset_ext_456'
)
complex_obj.extid
#=> 'preset_ext_456'

## find_by methods are available (stub implementations)
search_obj = IntegrationTest.new
search_obj.id = 'search_test'
search_obj.save

## find_by_objid returns nil (stub implementation)
search_obj = IntegrationTest.new
search_obj.id = 'search_test'
search_obj.save
found_by_objid = IntegrationTest.find_by_objid(search_obj.objid)
found_by_objid
#=> nil

## find_by_extid works with real implementation
@search_obj = IntegrationTest.new
@search_obj.id = 'search_test'
@search_obj.save
found_by_extid = IntegrationTest.find_by_extid(@search_obj.extid)
found_by_extid&.id
#=> "search_test"

## Both IDs remain stable across multiple accesses
stability_obj = IntegrationTest.new
first_objid = stability_obj.objid
first_extid = stability_obj.extid
second_objid = stability_obj.objid
second_extid = stability_obj.extid

## objid remains stable across accesses
stability_obj = IntegrationTest.new
first_objid = stability_obj.objid
second_objid = stability_obj.objid
first_objid == second_objid
#==> true

## extid remains stable across accesses
stability_obj = IntegrationTest.new
first_extid = stability_obj.extid
second_extid = stability_obj.extid
first_extid == second_extid
#==> true

## Feature dependency is enforced (external_identifier requires object_identifier)
# This is automatically handled by the feature system
IntegrationTest.features_enabled.include?(:object_identifier)
#==> true

## Objects work with existing Horreum save pattern
obj = IntegrationTest.new
obj.respond_to?(:save)
#==> true

## Objects work with existing Horreum exists pattern
obj = IntegrationTest.new
obj.respond_to?(:exists?)
#==> true

## Objects work with existing Horreum delete pattern
obj = IntegrationTest.new
obj.respond_to?(:delete!)
#==> true

# Cleanup test objects
@search_obj.destroy! rescue nil
