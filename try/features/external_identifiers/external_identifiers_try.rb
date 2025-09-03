# try/features/external_identifiers_try.rb

require_relative '../../helpers/test_helpers'

Familia.debug = false

# Test ExternalIdentifiers feature functionality

# Basic class using external identifiers
class ExternalIdTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier
  identifier_field :id
  field :id
  field :name
end

# Class with custom prefix
class CustomPrefixTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier, prefix: 'cust'
  identifier_field :id
  field :id
  field :name
end

# Class testing data integrity preservation
class ExternalDataIntegrityTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier
  identifier_field :id
  field :id
  field :name
end

# Test with existing external ID during initialization
@existing_ext_obj = ExternalDataIntegrityTest.new(id: 'test_id', extid: 'preset_ext_123', name: 'Preset External')

# Test objects for lazy generation and complex initialization
@lazy_obj = ExternalIdTest.new
@complex_obj = ExternalIdTest.new(id: 'complex_ext', name: 'Complex External')

## Feature depends on object_identifiers
ExternalIdTest.features_enabled.include?(:object_identifier)
#==> true

## External identifiers feature is included
ExternalIdTest.features_enabled.include?(:external_identifier)
#==> true

## Class has extid field defined
ExternalIdTest.respond_to?(:extid)
#==> true

## Object has extid accessor
obj = ExternalIdTest.new
obj.respond_to?(:extid)
#==> true

## External ID is generated from objid deterministically
obj = ExternalIdTest.new
obj.id = 'test_obj'
obj.name = 'Test Object'
objid = obj.objid
extid = obj.extid
# Same objid should always produce same extid
obj2 = ExternalIdTest.new
obj2.instance_variable_set(:@objid, objid)
obj2.extid == extid
#==> true

## External ID uses default 'ext' prefix
obj = ExternalIdTest.new
obj.extid.start_with?('ext_')
#==> true

## Custom prefix class uses specified prefix
custom_obj = CustomPrefixTest.new
custom_obj.extid.start_with?('cust_')
#==> true

## External ID is URL-safe base-36 format
obj = ExternalIdTest.new
extid = obj.extid
extid.match(/\Aext_[0-9a-z]+\z/)
#=*> nil

## Custom prefix external ID format is correct
custom_obj = CustomPrefixTest.new
extid = custom_obj.extid
extid.match(/\Acust_[0-9a-z]+\z/)
#=*> nil

## External ID is lazy - not generated until accessed
@lazy_obj.instance_variable_get(:@extid)
#=> nil

## External ID is generated when first accessed
@lazy_obj.extid
@lazy_obj.instance_variable_get(:@extid)
#=*> nil

## External ID value is stable across multiple calls
first_call = @lazy_obj.extid
second_call = @lazy_obj.extid
first_call == second_call
#==> true

## Data integrity: preset extid is preserved
@existing_ext_obj.extid
#=> "preset_ext_123"

## Data integrity: preset extid not regenerated
@existing_ext_obj.instance_variable_get(:@extid)
#=> "preset_ext_123"

## find_by_extid class method exists
ExternalIdTest.respond_to?(:find_by_extid)
#==> true

## find_by_extid returns correct type
result = ExternalIdTest.find_by_extid('nonexistent')
result.is_a?(ExternalIdTest) || result.nil?
#==> true

## External ID is deterministic from objid
test_objid = "01234567-89ab-7def-8fed-cba987654321"
obj1 = ExternalIdTest.new
obj1.instance_variable_set(:@objid, test_objid)
obj2 = ExternalIdTest.new
obj2.instance_variable_set(:@objid, test_objid)
obj1.extid == obj2.extid
#==> true

## External ID is different from objid
obj = ExternalIdTest.new
obj.objid != obj.extid
#==> true

## External ID persists through save/load cycle
save_obj = ExternalIdTest.new
save_obj.id = 'ext_save_test'
save_obj.name = 'External Save Test'
original_extid = save_obj.extid
save_obj.save
loaded_obj = ExternalIdTest.new(id: 'ext_save_test')
loaded_obj.extid == original_extid
#==> true

## Different objids produce different external IDs
obj1 = ExternalIdTest.new
obj2 = ExternalIdTest.new
obj1.extid != obj2.extid
#==> true

## extid field type is ExternalIdentifierFieldType
ExternalIdTest.field_types[:extid]
#=:> Familia::Features::ExternalIdentifier::ExternalIdentifierFieldType

## Feature options contain correct prefix
ExternalIdTest.feature_options(:external_identifier)[:prefix]
#=> "ext"

## Custom prefix feature options
CustomPrefixTest.feature_options(:external_identifier)[:prefix]
#=> "cust"

## External ID is shorter than UUID objid
obj = ExternalIdTest.new
obj.extid.length < obj.objid.length
#==> true

## External ID contains only lowercase alphanumeric after prefix
obj = ExternalIdTest.new
extid_suffix = obj.extid.split('_', 2)[1]
extid_suffix.match(/\A[0-9a-z]+\z/)
#=*> nil

## Complex initialization preserves lazy generation
@complex_obj.instance_variable_get(:@extid)
#=> nil

## External ID generation after complex initialization
@complex_obj.extid
#=*> nil

## find_by_extid works with saved objects
@test_obj = ExternalIdTest.new(id: 'findable_test', name: 'Test Object')
@test_obj.save
found_obj = ExternalIdTest.find_by_extid(@test_obj.extid)
found_obj&.id
#=> "findable_test"

## find_by_extid returns nil for nonexistent extids
ExternalIdTest.find_by_extid('nonexistent_extid')
#=> nil

## extid_lookup mapping is maintained
ExternalIdTest.extid_lookup[@test_obj.extid]
#=> "findable_test"

# Cleanup test objects
@test_obj.destroy! rescue nil
