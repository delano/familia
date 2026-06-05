# try/features/relationships/participation_each_record_try.rb
#
# frozen_string_literal: true

# Tests for issue #297: participates_in collections were created without any
# record/reference class, so `each_record` raised Familia::Problem
# ("requires a DataType with a :record_class (or :class) option ...").
#
# The fix declares participation collections with `record_class: <participant>`
# — a loading-only hint that lets `each_record` hydrate the stored participant
# identifiers via load_multi WITHOUT changing how the collection deserializes
# reads (members/member?/score keep the generic DataType semantics). This is
# deliberately narrower than the `class: + reference: true` used by `instances`
# and `unique_index` (which also want raw-string read semantics), so adding
# participation to a collection is transparent to existing readers. See the
# v2.10.0 migration notes for the rationale.

require 'stringio'
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
# The participation collection carries record_class (issue #297)
# ============================================================

## sorted_set participation collection carries the participant as record_class
@org.members.opts[:record_class]
#=> PERMember

## record_class is a loading-only hint: no serialization :class is set
@org.members.opts[:class]
#=> nil

## ...and it is NOT a reference collection (reads keep generic semantics)
@org.members.opts[:reference]
#=> nil

## Stored members are raw identifiers (a Familia object stores its identifier)
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

## set participation collection carries record_class (not a reference type)
@m1.add_to_per_org_crew(@org)
@m2.add_to_per_org_crew(@org)
[@org.crew.opts[:record_class], @org.crew.opts[:reference]]
#=> [PERMember, nil]

## each_record on a set yields the participants
records = []
@org.crew.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m2"]

## list participation collection carries record_class (not a reference type)
@m1.add_to_per_org_queue(@org)
@m3.add_to_per_org_queue(@org)
[@org.queue.opts[:record_class], @org.queue.opts[:reference]]
#=> [PERMember, nil]

## each_record on a list yields the participants
records = []
@org.queue.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m3"]

# ============================================================
# each_record on a class-level participation collection
# ============================================================

## class_participates_in collection carries record_class
PERMember.add_to_all_members(@m1)
PERMember.add_to_all_members(@m2)
[PERMember.all_members.opts[:record_class], PERMember.all_members.opts[:reference]]
#=> [PERMember, nil]

## each_record on the class-level collection yields the records
records = []
PERMember.all_members.each_record { |r| records << r }
records.map(&:member_id).sort
#=> ["m1", "m2"]

# ============================================================
# record_class does NOT change read semantics (the whole point of the
# narrower option): members/member? behave exactly as on a plain DataType.
# ============================================================

## members() returns identifiers exactly as a plain DataType would
@org.members.members.sort
#=> ["m1", "m2", "m3"]

## membership lookups by object still work
@org.members.member?(@m1)
#=> true

## A numeric-looking identifier still reads back as Integer — legacy DataType
## type-preservation is intact, because record_class adds no reference semantics
@n1 = PERMember.new(member_id: '789', created_at: Familia.now.to_i)
@n1.save
@n1.add_to_per_org_members(@org)
@org.members.members.include?(789)
#=> true

## member?(raw_string_id) keeps object-serialization semantics (issue #212
## limitation preserved: pass objects, not raw string identifiers)
@org.members.member?('789')
#=> false

## ...but each_record still loads the numeric-id participant (record_class drives loading)
ids = []
@org.members.each_record { |r| ids << r.member_id }
ids.include?('789')
#=> true

# ============================================================
# Regression guard: each_record stays quiet. record_class marks members as
# object identifiers, so the deserializing each() must NOT emit the per-member
# "raw fallback" warning it would otherwise log for non-JSON identifiers.
# ============================================================

## each_record emits no deserialize warnings for (non-JSON) string identifiers
@log_io = StringIO.new
@orig_logger = Familia.logger
Familia.logger = Familia::FamiliaLogger.new(@log_io)
begin
  @org.members.each_record { |r| }
ensure
  Familia.logger = @orig_logger
end
@log_io.string.scan(/Raw fallback/).size
#=> 0

# Teardown
@org.members.clear rescue nil
@org.crew.clear rescue nil
@org.queue.clear rescue nil
PERMember.all_members.clear rescue nil
[@m1, @m2, @m3, @n1].each { |m| m.destroy! rescue nil }
@org.destroy! rescue nil
