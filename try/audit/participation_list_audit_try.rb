# try/audit/participation_list_audit_try.rb
#
# Tests audit and repair for instance-level participation using List
# collections. Verifies that the type-aware audit logic works for lists
# (LRANGE) and that repair uses LREM to remove stale members.
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class AuditListOwner < Familia::Horreum
  feature :relationships

  identifier_field :oid
  field :oid
  field :name

  list :items
end

class AuditListItem < Familia::Horreum
  feature :relationships

  identifier_field :iid
  field :iid
  field :label

  participates_in AuditListOwner, :items, type: :list
end

# Clean up
begin
  existing = Familia.dbclient.keys('audit_list_owner:*')
  existing += Familia.dbclient.keys('audit_list_item:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditListOwner.instances.clear
AuditListItem.instances.clear

## Setup owner and list items
@owner = AuditListOwner.new(oid: 'lo-1', name: 'ListOwner')
@owner.save
@i1 = AuditListItem.new(iid: 'li-1', label: 'First')
@i1.save
@i2 = AuditListItem.new(iid: 'li-2', label: 'Second')
@i2.save
@i3 = AuditListItem.new(iid: 'li-3', label: 'Third')
@i3.save
@owner.add_items_instance(@i1)
@owner.add_items_instance(@i2)
@owner.add_items_instance(@i3)
@owner.items.size
#=> 3

## Collection key is a Redis list
Familia.dbclient.type(@owner.items.dbkey)
#=> "list"

## No stale members when all exist
AuditListItem.audit_participations.first[:stale_members].size
#=> 0

## Delete li-1, leaving it in the list
Familia.dbclient.del(@i1.dbkey)
@audit = AuditListItem.audit_participations
@audit.first[:stale_members].size
#=> 1

## Stale entry has correct identifier
@audit.first[:stale_members].first[:identifier]
#=> "li-1"

## Stale entry has correct collection_key
@audit.first[:stale_members].first[:collection_key]
#=> @owner.items.dbkey

## Stale entry has correct collection_name
@audit.first[:stale_members].first[:collection_name]
#=> :items

## Stale entry has correct reason
@audit.first[:stale_members].first[:reason]
#=> :object_missing

## Repair removes stale member from list collection
@result = AuditListItem.repair_participations!
@result[:stale_removed]
#=> 1

## li-1 is gone from the list
@owner.items.membersraw.include?('li-1')
#=> false

## li-2 remains in the list
@owner.items.membersraw.include?('li-2')
#=> true

## li-3 remains in the list
@owner.items.membersraw.include?('li-3')
#=> true

## List size is reduced after repair
@owner.items.size
#=> 2

## Repair uses LREM (list removal), verified by key type
Familia.dbclient.type(@owner.items.dbkey)
#=> "list"

## After repair, audit is clean
AuditListItem.audit_participations.first[:stale_members].size
#=> 0

## Multiple stale: delete two items, both detected
Familia.dbclient.del(@i2.dbkey)
Familia.dbclient.del(@i3.dbkey)
@audit = AuditListItem.audit_participations
@audit.first[:stale_members].size
#=> 2

## Multiple stale: repair removes both
@result = AuditListItem.repair_participations!
@result[:stale_removed]
#=> 2

## After multi-repair, list is empty
@owner.items.size
#=> 0

## Multiple owners: create second owner with overlapping items
@i4 = AuditListItem.new(iid: 'li-4', label: 'Fourth')
@i4.save
@i5 = AuditListItem.new(iid: 'li-5', label: 'Fifth')
@i5.save
@owner2 = AuditListOwner.new(oid: 'lo-2', name: 'ListOwner2')
@owner2.save
@owner.add_items_instance(@i4)
@owner.add_items_instance(@i5)
@owner2.add_items_instance(@i4)
@owner2.add_items_instance(@i5)
@owner.items.size + @owner2.items.size
#=> 4

## Delete li-4, stale in both owner collections
Familia.dbclient.del(@i4.dbkey)
@audit = AuditListItem.audit_participations
@total_stale = @audit.sum { |r| r[:stale_members].size }
@total_stale
#=> 2

## Repair removes from both owner collections
@result = AuditListItem.repair_participations!
@result[:stale_removed]
#=> 2

## Owner1 no longer has li-4
@owner.items.membersraw.include?('li-4')
#=> false

## Owner2 no longer has li-4
@owner2.items.membersraw.include?('li-4')
#=> false

## Owner1 still has li-5
@owner.items.membersraw.include?('li-5')
#=> true

## Owner2 still has li-5
@owner2.items.membersraw.include?('li-5')
#=> true

## Instances timeline was NOT modified by participation repair
AuditListItem.instances.size
#=> 5

# Teardown
begin
  existing = Familia.dbclient.keys('audit_list_owner:*')
  existing += Familia.dbclient.keys('audit_list_item:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditListOwner.instances.clear
AuditListItem.instances.clear
