# try/features/object_identifier/object_identifier_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Test ObjectIdentifier feature functionality

# Basic class using default UUID v7 generator
class BasicObjectTest < Familia::Horreum
  feature :object_identifier
  identifier_field :id
  field :id
  field :name
end

# Class using UUID v4 generator
class UuidV4Test < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4
  identifier_field :id
  field :id
  field :name
end

# Class using hex generator
class HexTest < Familia::Horreum
  feature :object_identifier, generator: :hex
  identifier_field :id
  field :id
  field :name
end

# Class using custom proc generator
class CustomProcTest < Familia::Horreum
  feature :object_identifier, generator: -> { "custom_#{SecureRandom.hex(4)}" }
  identifier_field :id
  field :id
  field :name
end

# Class testing data integrity preservation
class DataIntegrityTest < Familia::Horreum
  feature :object_identifier
  identifier_field :id
  field :id
  field :name
end

# Test with existing object ID during initialization
@existing_obj = DataIntegrityTest.new(id: 'test_id', objid: 'preset_id_123', name: 'Preset Object')

## Feature is available on class
BasicObjectTest.features_enabled.include?(:object_identifier)
#==> true

## Class has objid field defined
BasicObjectTest.respond_to?(:objid)
#==> true

## Object has objid accessor
obj = BasicObjectTest.new
obj.respond_to?(:objid)
#==> true

## Default generator creates UUID v7 format
obj = BasicObjectTest.new
obj.name = 'Test Object'
objid = obj.objid
objid.is_a?(String) && objid.length == 36 && objid.include?('-')
#==> true

## UUID v7 objid has correct format (8-4-4-4-12 characters)
obj = BasicObjectTest.new
obj.objid.match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
#=*> nil

## UUID v4 generator creates correct format
v4_obj = UuidV4Test.new
v4_objid = v4_obj.objid
v4_objid.match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
#=*> nil

## Hex generator creates hex string
hex_obj = HexTest.new
hex_objid = hex_obj.objid
hex_objid.is_a?(String) && hex_objid.length == 16 && hex_objid.match(/\A[0-9a-f]+\z/)
#==> true

## Custom proc generator works
custom_obj = CustomProcTest.new
custom_objid = custom_obj.objid
custom_objid.start_with?('custom_') && custom_objid.length == 15
#==> true

## objid is lazy - not generated until accessed
lazy_obj = BasicObjectTest.new
lazy_obj.instance_variable_get(:@objid)
#=> nil

## objid is generated when first accessed
lazy_obj = BasicObjectTest.new
lazy_obj.objid
lazy_obj
#=*> _.instance_variable_get(:@objid)

## objid is generated when first accessed (alternatve testcase expectation)
lazy_obj = BasicObjectTest.new
lazy_obj.objid
lazy_obj.instance_variable_get(:@objid)
#=<> nil

## objid value is stable across multiple calls
lazy_obj = BasicObjectTest.new
first_call = lazy_obj.objid
second_call = lazy_obj.objid
first_call == second_call
#==> true

## Data integrity: preset objid is preserved
@existing_obj.objid
#=> "preset_id_123"

## Data integrity: preset objid not regenerated
@existing_obj.instance_variable_get(:@objid)
#=> "preset_id_123"

## find_by_objid class method exists
BasicObjectTest.respond_to?(:find_by_objid)
#==> true

## find_by_objid returns correct type (stub for now)
BasicObjectTest.find_by_objid('nonexistent')
#=> nil

## Generated objid is URL-safe (no special chars except hyphens)
url_obj = BasicObjectTest.new
objid = url_obj.objid
objid
#=*> _.match(/\A[A-Za-z0-9\-]+\z/)

## Different objects get different objids
obj1 = BasicObjectTest.new
obj2 = BasicObjectTest.new
obj1.objid != obj2.objid
#==> true

## objid persists through save/load cycle
save_obj = BasicObjectTest.new
save_obj.id = 'save_test'
save_obj.name = 'Save Test'
original_objid = save_obj.objid
save_obj.save
loaded_obj = BasicObjectTest.new(id: 'save_test')
loaded_obj.objid == original_objid
#==> true

## Class with different generator has different objid pattern
basic_obj = BasicObjectTest.new
hex_obj = HexTest.new
basic_obj.objid.include?('-') && !hex_obj.objid.include?('-')
#==> true

## objid field type is ObjectIdentifierFieldType
BasicObjectTest.field_types[:objid]
#=:> Familia::Features::ObjectIdentifier::ObjectIdentifierFieldType

## Generator configuration is accessible through feature options
BasicObjectTest.feature_options(:object_identifier)[:generator]
#=> :uuid_v7

## UUID v4 class has correct generator configured
UuidV4Test.feature_options(:object_identifier)[:generator]
#=> :uuid_v4

## Hex class has correct generator configured
HexTest.feature_options(:object_identifier)[:generator]
#=> :hex

## Custom proc class has proc generator
CustomProcTest.feature_options(:object_identifier)[:generator]
#=:> Proc

## Empty initialization preserves nil objid for lazy generation
empty_obj = BasicObjectTest.new
empty_obj.instance_variable_get(:@objid)
#=> nil

## Objid generation works with complex initialization
complex_obj = BasicObjectTest.new(id: 'complex', name: 'Complex Object')
complex_obj
#=*> _.objid

## Test objid_lookup mapping when identifier set after objid generation (race condition fix)
# Create object without identifier, access objid first, then set identifier
race_obj = BasicObjectTest.new
generated_objid = race_obj.objid           # Generate objid before setting identifier
race_obj.id = "race_test_123"               # Set identifier after objid exists
race_obj.save                                # Save so find_by_objid can locate it
found = BasicObjectTest.find_by_objid(generated_objid)
found && found.id == "race_test_123"
#=> true
