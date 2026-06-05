# try/features/relationships/participation_each_record_try.rb
#
# frozen_string_literal: true

# Tests for issue #297: participates_in collections were created without the
# `class:` option, so `each_record` raised Familia::Problem ("requires a
# reference DataType with a :class option that responds to load_multi").
#
# The fix declares participation collections as proper reference types
# (`class: participant_class, reference: true`), matching the `instances`
# collection pattern (Horreum.inherited) and the unique_index fix (issue #276).
# This lets stored participant identifiers round-trip as raw strings and enables
# `each_record` to load the participant records via load_multi.

require_relative '../../support/helpers/test_helpers'

class PEROrg < Familia::Horreum
  feature :relationships

  identifier_field :org_id
  field :org_id
end

class PERMember < Familia::Horreum
  feature :relationships

  identifier_field :member_id
  field :member_id
  field :created_at

  # One participation per collection type to cover ZSET/SET/LIST
  participates_in PEROrg, :members, score: :created_at, type: :sorted_set
  participates_in PEROrg, :crew, type: :set
  participates_in PEROrg, :queue, type: :list

  # Class-level participation (collection holds instances of PERMember itself)
  class_participates_in :all_members, score: :created_at
end

# Setup
@org = PEROrg.new(org_id: 'org-per-1')
@org.save
@m1 = PERMember.new(member_id: 'm1', created_at: Familia.now.to_i)
@m1.save
@m2 = PERMember.new(member_id: 'm2', created_at: Familia.now.to_i + 5)
@m2.save
@m3 = PERMember.new(member_id: 'm3', created_at: Familia.now.to_i + 10)
@m3.save

@m1.add_to_per_org_members(@org)
@m2.add_to_per_org_members(@org)
@m3.add_to_per_org_members(@org)

# ============================================================
# The participation collection is a proper reference type
# ============================================================

## sorted_set participation collection carries the participant class
@org.members.opts[:class]
#=> PERMember

## sorted_set participation collection is a reference type
@org.members.opts[:reference]
#=> true

## Stored members are raw identifiers (not JSON-encoded)
@org.members.membersraw.sort
#=> ["m1", "m2", "m3"]

# ============================================================
# each_record on a participates_in sorted set (issue #297)
# ============================================================

## each_record no longer raises and yields Horreum records
records = []
@org.members.each_record { |r| records << r }
records.all? { |r| r.is_a?(PERMember) }
#=> true

## each_record yields every participant (by identifier)
records = []
@org.members.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m2", "m3"]

## each_record returns an Enumerator when no block is given
@org.members.each_record.class
#=> Enumerator

## each_record Enumerator composes with Enumerable
@org.members.each_record.map(&:member_id).sort
#=> ["m1", "m2", "m3"]

## each_record honors batch_size
records = []
@org.members.each_record(batch_size: 1) { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m2", "m3"]

## each_record honors the sorted-set since: filter
records = []
@org.members.each_record(since: @m2.created_at) { |r| records << r }
records.map(&:member_id).sort
#=> ["m2", "m3"]

## each_record skips ghost entries (member points at a deleted record)
@org.members.add('m-ghost', Familia.now.to_f)
records = []
@org.members.each_record { |r| records << r }
result = records.map(&:member_id).sort
@org.members.remove('m-ghost')
result
#=> ["m1", "m2", "m3"]

# ============================================================
# each_record on a participates_in set and list
# ============================================================

## set participation collection is a reference type pointing at the participant
@m1.add_to_per_org_crew(@org)
@m2.add_to_per_org_crew(@org)
[@org.crew.opts[:class], @org.crew.opts[:reference]]
#=> [PERMember, true]

## each_record on a set yields the participants
records = []
@org.crew.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m2"]

## list participation collection is a reference type pointing at the participant
@m1.add_to_per_org_queue(@org)
@m3.add_to_per_org_queue(@org)
[@org.queue.opts[:class], @org.queue.opts[:reference]]
#=> [PERMember, true]

## each_record on a list yields the participants
records = []
@org.queue.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m3"]

# ============================================================
# each_record on a class-level participation collection
# ============================================================

## class_participates_in collection carries the class as its reference type
PERMember.add_to_all_members(@m1)
PERMember.add_to_all_members(@m2)
[PERMember.all_members.opts[:class], PERMember.all_members.opts[:reference]]
#=> [PERMember, true]

## each_record on the class-level collection yields the records
records = []
PERMember.all_members.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m2"]

# ============================================================
# Regression guard: members() still returns raw identifier strings
# ============================================================

## members() returns raw identifier strings (object lookups remain unchanged)
@org.members.members.sort
#=> ["m1", "m2", "m3"]

## membership lookups by object still work (issue #212 behavior preserved)
@org.members.member?(@m1)
#=> true

# ============================================================
# Numeric-string identifiers: reference reads normalize to the
# stored String (not JSON-coerced to Integer), and raw-string
# lookups now match (resolving the issue #212 limitation for
# auto-created participation collections). See migration notes.
# ============================================================

## a numeric-looking identifier reads back from members as a String (not Integer)
@n1 = PERMember.new(member_id: '456', created_at: Familia.now.to_i)
@n1.save
@n1.add_to_per_org_members(@org)
@org.members.members.include?('456')
#=> true

## ...and is not coerced to an Integer
@org.members.members.include?(456)
#=> false

## member?(raw_string_id) now matches the stored identifier
@org.members.member?('456')
#=> true

## each_record loads the numeric-id participant like any other
ids = []
@org.members.each_record { |r| ids << r.member_id }
ids.include?('456')
#=> true

# Teardown
@org.members.clear rescue nil
@org.crew.clear rescue nil
@org.queue.clear rescue nil
PERMember.all_members.clear rescue nil
[@m1, @m2, @m3, @n1].each { |m| m.destroy! rescue nil }
@org.destroy! rescue nil
