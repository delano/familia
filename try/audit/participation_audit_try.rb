# try/audit/participation_audit_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class AuditParticipant < Familia::Horreum
  feature :relationships

  identifier_field :pid
  field :pid
  field :name
  field :created_at

  class_participates_in :all_participants, score: :created_at
end

# Clean up any leftover test data
begin
  existing = Familia.dbclient.keys('audit_participant:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditParticipant.instances.clear
AuditParticipant.all_participants.clear

## audit_participations exists as class method
AuditParticipant.respond_to?(:audit_participations)
#=> true

## audit_participations returns array
AuditParticipant.audit_participations.is_a?(Array)
#=> true

## audit_participations on empty collection returns no stale members
@result = AuditParticipant.audit_participations
@result.first[:stale_members]
#=> []

## audit_participations reports correct collection_name
@result.first[:collection_name]
#=> :all_participants

## Create objects and add to participation collection
@p1 = AuditParticipant.new(pid: 'ap-1', name: 'Alpha', created_at: Familia.now.to_f)
@p1.save
@p2 = AuditParticipant.new(pid: 'ap-2', name: 'Beta', created_at: Familia.now.to_f)
@p2.save
@p3 = AuditParticipant.new(pid: 'ap-3', name: 'Gamma', created_at: Familia.now.to_f)
@p3.save
AuditParticipant.add_to_all_participants(@p1, Familia.now.to_f)
AuditParticipant.add_to_all_participants(@p2, Familia.now.to_f)
AuditParticipant.add_to_all_participants(@p3, Familia.now.to_f)
AuditParticipant.all_participants.size
#=> 3

## Consistent state: no stale members in collection
@result = AuditParticipant.audit_participations
@result.first[:stale_members].size
#=> 0

## Stale detection: delete object key but leave collection member
Familia.dbclient.del(@p1.dbkey)
@result = AuditParticipant.audit_participations
@result.first[:stale_members].size
#=> 1

## Stale entry has correct identifier
@result.first[:stale_members].first[:identifier]
#=> "ap-1"

## Stale entry has correct reason
@result.first[:stale_members].first[:reason]
#=> :object_missing

## Stale entry includes collection_name
@result.first[:stale_members].first[:collection_name]
#=> :all_participants

## Collection still has 3 members (stale one not removed by audit)
AuditParticipant.all_participants.size
#=> 3

## Multiple stale: delete another object key
Familia.dbclient.del(@p2.dbkey)
@result = AuditParticipant.audit_participations
@result.first[:stale_members].size
#=> 2

## Multiple stale: identifiers are detected
@stale_ids = @result.first[:stale_members].map { |s| s[:identifier] }.sort
@stale_ids
#=> ["ap-1", "ap-2"]

## Valid members are not flagged
@result.first[:stale_members].none? { |s| s[:identifier] == 'ap-3' }
#=> true

## audit_participations accepts sample_size parameter
@p1_restored = AuditParticipant.new(pid: 'ap-1', name: 'Alpha', created_at: Familia.now.to_f)
@p1_restored.save
@p2_restored = AuditParticipant.new(pid: 'ap-2', name: 'Beta', created_at: Familia.now.to_f)
@p2_restored.save
@result = AuditParticipant.audit_participations(sample_size: 1)
@result.first[:stale_members].size <= 1
#=> true

## Instances timeline is independent from participation collection
AuditParticipant.instances.size
#=> 3

# Teardown
begin
  existing = Familia.dbclient.keys('audit_participant:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditParticipant.instances.clear
AuditParticipant.all_participants.clear
