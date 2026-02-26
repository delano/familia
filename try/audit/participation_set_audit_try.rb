# try/audit/participation_set_audit_try.rb
#
# Tests audit and repair for instance-level participation using UnsortedSet
# collections. Verifies that the type-aware removal logic works for sets.
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class AuditSetOwner < Familia::Horreum
  feature :relationships

  identifier_field :oid
  field :oid
  field :name

  set :tags
end

class AuditTag < Familia::Horreum
  feature :relationships

  identifier_field :tid
  field :tid
  field :label

  participates_in AuditSetOwner, :tags, type: :set
end

# Clean up
begin
  existing = Familia.dbclient.keys('audit_set_owner:*')
  existing += Familia.dbclient.keys('audit_tag:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditSetOwner.instances.clear
AuditTag.instances.clear

## Setup owner and tags
@owner = AuditSetOwner.new(oid: 'owner-1', name: 'Owner')
@owner.save
@t1 = AuditTag.new(tid: 'tag-1', label: 'Red')
@t1.save
@t2 = AuditTag.new(tid: 'tag-2', label: 'Blue')
@t2.save
@owner.add_tags_instance(@t1)
@owner.add_tags_instance(@t2)
@owner.tags.size
#=> 2

## No stale members when all exist
AuditTag.audit_participations.first[:stale_members].size
#=> 0

## Delete tag-1, leaving it in the set
Familia.dbclient.del(@t1.dbkey)
@audit = AuditTag.audit_participations
@audit.first[:stale_members].size
#=> 1

## Stale entry has correct identifier
@audit.first[:stale_members].first[:identifier]
#=> "tag-1"

## Stale entry has correct collection_key
@audit.first[:stale_members].first[:collection_key]
#=> @owner.tags.dbkey

## Repair removes stale from set collection
@result = AuditTag.repair_participations!
@result[:stale_removed]
#=> 1

## tag-1 is gone from the set
@owner.tags.membersraw.include?('tag-1')
#=> false

## tag-2 remains in the set
@owner.tags.membersraw.include?('tag-2')
#=> true

## Repair uses SREM (set removal), verified by key type
Familia.dbclient.type(@owner.tags.dbkey)
#=> "set"

## After repair, audit is clean
AuditTag.audit_participations.first[:stale_members].size
#=> 0

# Teardown
begin
  existing = Familia.dbclient.keys('audit_set_owner:*')
  existing += Familia.dbclient.keys('audit_tag:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditSetOwner.instances.clear
AuditTag.instances.clear
