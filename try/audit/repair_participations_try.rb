# try/audit/repair_participations_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class RepairParticipant < Familia::Horreum
  feature :relationships

  identifier_field :rpid
  field :rpid
  field :name
  field :created_at

  class_participates_in :all_repair_participants, score: :created_at
end

# Clean up any leftover test data
begin
  existing = Familia.dbclient.keys('repair_participant:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairParticipant.instances.clear
RepairParticipant.all_repair_participants.clear

## repair_participations! exists as class method
RepairParticipant.respond_to?(:repair_participations!)
#=> true

## Create objects and populate participation collection
@rp1 = RepairParticipant.new(rpid: 'rp-1', name: 'One', created_at: Familia.now.to_f)
@rp1.save
@rp2 = RepairParticipant.new(rpid: 'rp-2', name: 'Two', created_at: Familia.now.to_f)
@rp2.save
@rp3 = RepairParticipant.new(rpid: 'rp-3', name: 'Three', created_at: Familia.now.to_f)
@rp3.save
RepairParticipant.add_to_all_repair_participants(@rp1, Familia.now.to_f)
RepairParticipant.add_to_all_repair_participants(@rp2, Familia.now.to_f)
RepairParticipant.add_to_all_repair_participants(@rp3, Familia.now.to_f)
RepairParticipant.all_repair_participants.size
#=> 3

## Introduce stale member: delete object key but leave in collection
Familia.dbclient.del(@rp1.dbkey)
RepairParticipant.audit_participations.first[:stale_members].size
#=> 1

## repair_participations! removes stale member from collection
@result = RepairParticipant.repair_participations!
@result[:stale_removed]
#=> 1

## After repair, stale member is gone from the raw collection
RepairParticipant.all_repair_participants.membersraw.include?('rp-1')
#=> false

## After repair, collection size is reduced
RepairParticipant.all_repair_participants.size
#=> 2

## After repair, valid members remain in raw collection
RepairParticipant.all_repair_participants.membersraw.include?('rp-2')
#=> true

## After repair, second valid member remains in raw collection
RepairParticipant.all_repair_participants.membersraw.include?('rp-3')
#=> true

## Instances timeline is NOT modified by repair_participations!
RepairParticipant.instances.size
#=> 3

## Instances timeline still contains even the deleted object entry
RepairParticipant.instances.member?('rp-1')
#=> true

## After repair, audit shows clean state
RepairParticipant.audit_participations.first[:stale_members].size
#=> 0

## Multiple stale: delete two objects, repair removes both
Familia.dbclient.del(@rp2.dbkey)
Familia.dbclient.del(@rp3.dbkey)
@result = RepairParticipant.repair_participations!
@result[:stale_removed]
#=> 2

## After multi-repair, collection is empty
RepairParticipant.all_repair_participants.size
#=> 0

## repair_participations! on clean state is a no-op
@rp4 = RepairParticipant.new(rpid: 'rp-4', name: 'Four', created_at: Familia.now.to_f)
@rp4.save
RepairParticipant.add_to_all_repair_participants(@rp4, Familia.now.to_f)
@result = RepairParticipant.repair_participations!
@result[:stale_removed]
#=> 0

## No-op repair does not affect collection
RepairParticipant.all_repair_participants.size
#=> 1

## repair_participations! accepts pre-computed audit results
Familia.dbclient.del(@rp4.dbkey)
@audit = RepairParticipant.audit_participations
@result = RepairParticipant.repair_participations!(@audit)
@result[:stale_removed]
#=> 1

## After pre-computed repair, collection is clean
RepairParticipant.all_repair_participants.size
#=> 0

## Expired key: setup objects and populate collection
@rp5 = RepairParticipant.new(rpid: 'rp-5', name: 'Five', created_at: Familia.now.to_f)
@rp5.save
@rp6 = RepairParticipant.new(rpid: 'rp-6', name: 'Six', created_at: Familia.now.to_f)
@rp6.save
RepairParticipant.add_to_all_repair_participants(@rp5, Familia.now.to_f)
RepairParticipant.add_to_all_repair_participants(@rp6, Familia.now.to_f)
Familia.dbclient.del(@rp5.dbkey)
@expired_audit = RepairParticipant.audit_participations
@expired_audit.first[:stale_members].size
#=> 1

## Expired key: delete collection key between audit and repair
@collection_key = RepairParticipant.all_repair_participants.dbkey
Familia.dbclient.del(@collection_key)
Familia.dbclient.type(@collection_key)
#=> "none"

## Expired key: repair returns stale_removed 0 when collection key is gone
@result = RepairParticipant.repair_participations!(@expired_audit)
@result[:stale_removed]
#=> 0

## Nil collection_key in stale entry is skipped
@nil_key_audit = [{
  collection_name: :all_repair_participants,
  stale_members: [
    { identifier: 'rp-fake', collection_key: nil, reason: :object_missing }
  ]
}]
@result = RepairParticipant.repair_participations!(@nil_key_audit)
@result[:stale_removed]
#=> 0

## Nil identifier in stale entry is skipped
@nil_id_audit = [{
  collection_name: :all_repair_participants,
  stale_members: [
    { identifier: nil, collection_key: 'repair_participant:all_repair_participants', reason: :object_missing }
  ]
}]
@result = RepairParticipant.repair_participations!(@nil_id_audit)
@result[:stale_removed]
#=> 0

## Both nil collection_key and nil identifier are skipped in mixed input
@mixed_nil_audit = [{
  collection_name: :all_repair_participants,
  stale_members: [
    { identifier: 'rp-fake', collection_key: nil, reason: :object_missing },
    { identifier: nil, collection_key: 'repair_participant:all_repair_participants', reason: :object_missing }
  ]
}]
@result = RepairParticipant.repair_participations!(@mixed_nil_audit)
@result[:stale_removed]
#=> 0

# Teardown
begin
  existing = Familia.dbclient.keys('repair_participant:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairParticipant.instances.clear
RepairParticipant.all_repair_participants.clear
