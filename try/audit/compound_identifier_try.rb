# try/audit/compound_identifier_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class CompoundIdModel < Familia::Horreum
  identifier_field :cid
  field :cid
  field :name
  field :updated
end

# Clean up any leftover test data
begin
  existing = Familia.dbclient.keys('compound_id_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
CompoundIdModel.instances.clear

## extract_identifier_from_key with simple identifier
CompoundIdModel.extract_identifier_from_key('compound_id_model:simple:object')
#=> "simple"

## extract_identifier_from_key with compound identifier containing delimiter
CompoundIdModel.extract_identifier_from_key('compound_id_model:foo:bar:object')
#=> "foo:bar"

## extract_identifier_from_key with triple-segment compound identifier
CompoundIdModel.extract_identifier_from_key('compound_id_model:a:b:c:object')
#=> "a:b:c"

## extract_identifier_from_key returns nil for key with wrong prefix
CompoundIdModel.extract_identifier_from_key('wrong_prefix:foo:object')
#=> nil

## extract_identifier_from_key returns nil for key with wrong suffix
CompoundIdModel.extract_identifier_from_key('compound_id_model:foo:wrong')
#=> nil

## Save object with compound identifier containing delimiter
@obj = CompoundIdModel.new(cid: 'part1:part2', name: 'Compound')
@obj.save
@obj.identifier
#=> "part1:part2"

## Saved object has correct dbkey
@obj.dbkey
#=> "compound_id_model:part1:part2:object"

## scan_identifiers finds the compound identifier intact
@ids = CompoundIdModel.send(:scan_identifiers)
@ids.include?('part1:part2')
#=> true

## audit_instances reports no phantoms for compound id object
@audit = CompoundIdModel.audit_instances
@audit[:phantoms]
#=> []

## audit_instances reports no missing for compound id object
@audit[:missing]
#=> []

## audit_instances counts match with compound id
@audit[:count_timeline] == @audit[:count_scan]
#=> true

## Save a second object with different compound id
@obj2 = CompoundIdModel.new(cid: 'x:y:z', name: 'Triple')
@obj2.save
CompoundIdModel.instances.size
#=> 2

## scan_identifiers finds both compound identifiers
@ids2 = CompoundIdModel.send(:scan_identifiers)
@ids2.include?('part1:part2') && @ids2.include?('x:y:z')
#=> true

## rebuild_instances preserves compound identifiers
CompoundIdModel.instances.clear
@count = CompoundIdModel.rebuild_instances
@count
#=> 2

## After rebuild, compound identifiers are present in instances
CompoundIdModel.in_instances?('part1:part2')
#=> true

## Second compound identifier also present after rebuild
CompoundIdModel.in_instances?('x:y:z')
#=> true

## Mix of simple and compound identifiers
@obj3 = CompoundIdModel.new(cid: 'simple-id', name: 'Simple')
@obj3.save
@ids3 = CompoundIdModel.send(:scan_identifiers)
@ids3.size
#=> 3

## All identifier types found by scan_identifiers
@ids3.include?('part1:part2') && @ids3.include?('x:y:z') && @ids3.include?('simple-id')
#=> true

## health_check works with compound identifiers
@report = CompoundIdModel.health_check
@report.instances[:phantoms].empty? && @report.instances[:missing].empty?
#=> true

# Teardown
begin
  existing = Familia.dbclient.keys('compound_id_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
CompoundIdModel.instances.clear
