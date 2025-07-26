# try/features/relatable_objects_try.rb

# Test RelatableObject feature functionality

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

class RelatableTest < Familia::Horreum
  feature :relatable_object
  identifier_field :id
  field :id
  field :name
end

class RelatedTest < Familia::Horreum
  feature :relatable_object
  identifier_field :id
  field :id
  field :name
end

class NonRelatableTest < Familia::Horreum
  identifier_field :id
  field :id
  field :name
end

# Setup test objects
@relatable_obj = RelatableTest.new
@relatable_obj.id = 'test_rel_1'
@relatable_obj.name = 'Test Relatable 1'

@related_obj = RelatedTest.new
@related_obj.id = 'test_rel_2'
@related_obj.name = 'Test Related 2'

@non_relatable = NonRelatableTest.new
@non_relatable.id = 'test_non_rel'
@non_relatable.name = 'Non Relatable'

## Class has RelatableObject methods mixed in
RelatableTest.respond_to?(:relatable_objids)
#=> true

## Class has owners class method
RelatableTest.respond_to?(:owners)
#=> true

## Class has relatable? method
RelatableTest.respond_to?(:relatable?)
#=> true

## Class has generate_objid method
RelatableTest.respond_to?(:generate_objid)
#=> true

## Class has generate_extid method
RelatableTest.respond_to?(:generate_extid)
#=> true

## Class has find_by_objid method
RelatableTest.respond_to?(:find_by_objid)
#=> true

## Object has objid method
@relatable_obj.respond_to?(:objid)
#=> true

## Object has extid method
@relatable_obj.respond_to?(:extid)
#=> true

## Object has api_version field
@relatable_obj.respond_to?(:api_version)
#=> true

## Object has owner? method
@relatable_obj.respond_to?(:owner?)
#=> true

## Object has owned? method
@relatable_obj.respond_to?(:owned?)
#=> true

## Object has relatable_objid alias
@relatable_obj.respond_to?(:relatable_objid)
#=> true

## Object has external_identifier alias
@relatable_obj.respond_to?(:external_identifier)
#=> true

## objid is lazily generated on first access
@relatable_obj.objid
#=:> String

## objid is a UUID v7 format
objid = @relatable_obj.objid
objid.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
#=> true

## objid is cached after first generation
objid1 = @relatable_obj.objid
objid2 = @related_obj.objid
[objid1, objid2]
#=/=> _[0].eql?(_[1])

## extid is lazily generated on first access
@relatable_obj.extid
#=:> String

## extid starts with 'ext_' prefix (from our mock)
@relatable_obj.extid.start_with?('ext_')
#=> true

## extid is cached after first generation
extid1 = @relatable_obj.extid
extid2 = @related_obj.extid
[extid1, extid2]
#=/=> _[0].eql?(_[1])

## api_version defaults to 'v2'
@relatable_obj.api_version
#=> 'v2'

## relatable_objid is alias for objid
[@relatable_obj.relatable_objid, @relatable_obj.objid]
#==> _[0].eql?(_[1])

## external_identifier is alias for extid
[@relatable_obj.external_identifier, @relatable_obj.extid]
#==> _[0].eql?(_[1])

## relatable? prevents self-ownership (same class)
RelatableTest.relatable?(@relatable_obj)
#=!> V2::Features::RelatableObjectError

## relatable? returns true for different relatable classes
RelatableTest.relatable?(@related_obj)
#=> true

## relatable? raises error for non-relatable objects
RelatableTest.relatable?(@non_relatable)
#=!> V2::Features::RelatableObjectError


## relatable? with block executes block for relatable objects
result = nil
RelatableTest.relatable?(@related_obj) do
  result = "executed"
end
result
#=> "executed"

## owned? returns false when no owner is set
@relatable_obj.owned?
#=> false

## owner? returns false when objects are not related
@relatable_obj.owner?(@related_obj)
#=> false

## generate_objid creates UUID v7
generated_id = RelatableTest.generate_objid
generated_id.match?(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
#=> true

## generate_extid creates external ID
RelatableTest.generate_extid
#==> _.start_with?('ext_')
#==> _.size == 54

## find_by_objid returns nil for empty objid
result = RelatableTest.find_by_objid('')
result.nil?
#=> true

## find_by_objid returns nil for nil objid
result = RelatableTest.find_by_objid(nil)
result.nil?
#=> true

## Class has relatable_objids sorted set
objids_set = RelatableTest.relatable_objids
objids_set.class.name
#=> "Familia::SortedSet"

## Class has owners hash key
owners_hash = RelatableTest.owners
owners_hash.class.name
#=> "Familia::HashKey"

## Objects can be persisted and retrieved
@relatable_obj.save
retrieved = RelatableTest.find(@relatable_obj.id)
retrieved.id == @relatable_obj.id
#=> true

## API version is preserved when persisting
retrieved = RelatableTest.find(@relatable_obj.id)
retrieved.api_version
#=> 'v2'

## Objid is preserved when persisting
original_objid = @relatable_obj.objid
retrieved = RelatableTest.find(@relatable_obj.id)
retrieved.objid == original_objid
#=> true

## Extid is preserved when persisting
original_extid = @relatable_obj.extid
retrieved = RelatableTest.find(@relatable_obj.id)
retrieved.extid == original_extid
#=> true

# Cleanup
@relatable_obj.destroy! if @relatable_obj
@related_obj.destroy! if @related_obj
@non_relatable.destroy! if @non_relatable
