# try/features/external_identifier/external_identifier_try.rb

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Test ExternalIdentifier feature functionality

# Basic class using external_identifier
class ExternalIdTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier
  identifier_field :id
  field :id
  field :name
end

# Class with custom prefix (uses default format template)
class CustomPrefixTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier, prefix: 'cust'
  identifier_field :id
  field :id
  field :name
end

# Class with custom format template (no underscore)
class CustomFormatTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier, format: '%{prefix}-%{id}'
  identifier_field :id
  field :id
  field :name
end

# Class with format template without prefix placeholder
class NoPrefixFormatTest < Familia::Horreum
  feature :object_identifier
  feature :external_identifier, format: 'api/%{id}'
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

## Feature depends on object_identifier
ExternalIdTest.features_enabled.include?(:object_identifier)
#==> true

## External identifier feature is included
ExternalIdTest.features_enabled.include?(:external_identifier)
#==> true

## Class has extid field defined
ExternalIdTest.respond_to?(:extid)
#==> true

## Object has extid accessor
obj = ExternalIdTest.new
obj.respond_to?(:extid)
#==> true

## External ID is generated from objid deterministically for same object
obj = ExternalIdTest.new
obj.id = 'test_obj'
obj.name = 'Test Object'
objid = obj.objid
extid = obj.extid
# Multiple calls to extid on same object should return same value
obj.extid == extid
#==> true

## External ID uses default 'ext' prefix
obj = ExternalIdTest.new
obj.extid.start_with?('ext_')
#==> true

## Custom prefix class uses specified prefix
custom_obj = CustomPrefixTest.new
custom_obj.extid.start_with?('cust_')
#==> true

## Custom format with hyphen separator
format_obj = CustomFormatTest.new
format_obj.extid.start_with?('ext-')
#==> true

## Custom format uses hyphen not underscore
format_obj = CustomFormatTest.new
extid = format_obj.extid
extid.include?('-') && !extid.include?('_')
#==> true

## Format without prefix placeholder uses literal format
no_prefix_obj = NoPrefixFormatTest.new
no_prefix_obj.extid.start_with?('api/')
#==> true

## Format without prefix does not include underscore
no_prefix_obj = NoPrefixFormatTest.new
extid = no_prefix_obj.extid
!extid.include?('_') && !extid.include?('ext')
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

## External ID is deterministic within same object
obj = ExternalIdTest.new
obj.id = 'deterministic_test'
first_extid = obj.extid
second_extid = obj.extid
first_extid == second_extid
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

## Feature options contain default format
ExternalIdTest.feature_options(:external_identifier)[:format]
#=> "%{prefix}_%{id}"

## Custom prefix feature options
CustomPrefixTest.feature_options(:external_identifier)[:prefix]
#=> "cust"

## Custom format feature options
CustomFormatTest.feature_options(:external_identifier)[:format]
#=> "%{prefix}-%{id}"

## No prefix format feature options
NoPrefixFormatTest.feature_options(:external_identifier)[:format]
#=> "api/%{id}"

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

## Test 1: Changing extid value (should work after bug fix)
bug_test_obj = ExternalIdTest.new(id: 'bug_test', name: 'Bug Test Object')
bug_test_obj.save
bug_test_obj.extid = 'new_extid_value'
bug_test_obj.extid
#=> "new_extid_value"

## Test 2: find_by_extid with deleted object (should work after bug fix)
delete_test_obj = ExternalIdTest.new(id: 'delete_test', name: 'Delete Test')
delete_test_obj.save
test_extid = delete_test_obj.extid
# Delete the object directly from Valkey/Redis to simulate cleanup scenario
ExternalIdTest.dbclient.del(delete_test_obj.dbkey)
# Now try to find by extid - this should clean up mapping and return nil
ExternalIdTest.find_by_extid(test_extid)
#=> nil

## Test 3: destroy! method (should work after bug fix)
destroy_test_obj = ExternalIdTest.new(id: 'destroy_test', name: 'Destroy Test')
destroy_test_obj.save
destroy_extid = destroy_test_obj.extid
destroy_test_obj.destroy!
# Verify mapping was cleaned up
ExternalIdTest.extid_lookup.key?(destroy_extid)
#=> false
