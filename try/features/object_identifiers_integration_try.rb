# try/features/object_identifiers_integration_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

# Integration test for ObjectIdentifiers and ExternalIdentifiers features together

# Class using both features with defaults
class IntegrationTest < Familia::Horreum
  feature :external_identifiers  # This depends on :object_identifiers
  identifier_field :id
  field :id
  field :name
  field :email
end

# Class with custom configurations for both features
class CustomIntegrationTest < Familia::Horreum
  feature :object_identifiers, generator: :hex
  feature :external_identifiers, prefix: 'custom'
  identifier_field :id
  field :id
  field :name
end

# Class testing full lifecycle with Redis persistence
class PersistenceTest < Familia::Horreum
  feature :external_identifiers
  identifier_field :id
  field :id
  field :name
  field :created_at
end

# Setup test objects
@integration_obj = IntegrationTest.new(id: 'integration_1', name: 'Integration Test', email: 'test@example.com')
@custom_obj = CustomIntegrationTest.new(id: 'custom_1', name: 'Custom Test')

## Both features are automatically included
IntegrationTest.features_enabled.include?(:object_identifiers) && IntegrationTest.features_enabled.include?(:external_identifiers)
#==> true

## Object has both objid and extid accessors
obj = IntegrationTest.new
obj.respond_to?(:objid) && obj.respond_to?(:extid)
#==> true

## Both find methods are available
IntegrationTest.respond_to?(:find_by_objid) && IntegrationTest.respond_to?(:find_by_extid)
#==> true

## objid and extid are different values
obj = IntegrationTest.new
obj.objid != obj.extid
#==> true

## extid is deterministically generated from objid
obj = IntegrationTest.new
original_objid = obj.objid
original_extid = obj.extid
# Create new object with same objid
obj2 = IntegrationTest.new
obj2.instance_variable_set(:@objid, original_objid)
obj2.extid == original_extid
#==> true

## Custom configuration affects both features
@custom_obj.objid.match(/\A[0-9a-f]{16}\z/) && @custom_obj.extid.start_with?('custom_')
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
loaded_obj.objid == original_objid && loaded_obj.extid == original_extid
#==> true

## Lazy generation works for both fields independently
lazy_obj = IntegrationTest.new
lazy_obj.instance_variable_get(:@objid).nil? && lazy_obj.instance_variable_get(:@extid).nil?
#==> true

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
IntegrationTest.field_types[:objid].is_a?(Familia::Features::ObjectIdentifiers::ObjectIdentifierFieldType)
#==> true

## ObjectIdentifier fields have correct types in field registry
IntegrationTest.field_types[:objid].class.ancestors.include?(Familia::Features::ObjectIdentifiers::ObjectIdentifierFieldType)
#==> true

## ExternalIdentifier fields have correct types in field registry
IntegrationTest.field_types[:extid].class.ancestors.include?(Familia::Features::ExternalIdentifiers::ExternalIdentifierFieldType)
#==> true

## Feature options are preserved for both features
opts = IntegrationTest.feature_options
opts.key?(:object_identifiers) && opts.key?(:external_identifiers)
#==> true

## Default configurations are applied correctly
IntegrationTest.feature_options(:object_identifiers)[:generator] == :uuid_v7 &&
IntegrationTest.feature_options(:external_identifiers)[:prefix]
#=> "ext"

## Custom configurations are applied correctly
CustomIntegrationTest.feature_options(:object_identifiers)[:generator] == :hex &&
CustomIntegrationTest.feature_options(:external_identifiers)[:prefix] == "custom"
#==> true

## Both IDs are URL-safe
obj = IntegrationTest.new
objid_safe = obj.objid.match(/\A[A-Za-z0-9\-]+\z/)
extid_safe = obj.extid.match(/\A[a-z0-9_]+\z/)
objid_safe && extid_safe
#==> true

## Data integrity preserved during complex initialization
complex_obj = IntegrationTest.new(
  id: 'complex_integration',
  name: 'Complex Integration',
  email: 'complex@test.com',
  objid: 'preset_objid_123',
  extid: 'preset_ext_456'
)
complex_obj.objid == 'preset_objid_123' && complex_obj.extid == 'preset_ext_456'
#==> true

## find_by methods are available (stub implementations)
search_obj = IntegrationTest.new
search_obj.id = 'search_test'
search_obj.save
found_by_objid = IntegrationTest.find_by_objid(search_obj.objid)
found_by_extid = IntegrationTest.find_by_extid(search_obj.extid)
# Current stub implementations return nil
found_by_objid.nil? && found_by_extid.nil?
#==> true

## Both IDs remain stable across multiple accesses
stability_obj = IntegrationTest.new
first_objid = stability_obj.objid
first_extid = stability_obj.extid
second_objid = stability_obj.objid
second_extid = stability_obj.extid
first_objid == second_objid && first_extid == second_extid
#==> true

## Feature dependency is enforced (external_identifiers requires object_identifiers)
# This is automatically handled by the feature system
IntegrationTest.features_enabled.include?(:object_identifiers)
#==> true

## Both features work with existing Horreum patterns
obj = IntegrationTest.new
obj.respond_to?(:save) && obj.respond_to?(:exists?) && obj.respond_to?(:delete!)
#==> true
