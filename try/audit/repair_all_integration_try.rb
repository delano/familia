# try/audit/repair_all_integration_try.rb
#
# Tests repair_all! integration across all three repair dimensions:
# instances timeline, unique indexes, and participation collections.
# Each dimension has corruption introduced before repair.
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class IntegrationItem < Familia::Horreum
  feature :relationships

  identifier_field :iid
  field :iid
  field :name
  field :email
  field :created_at

  unique_index :email, :email_lookup
  class_participates_in :all_integration_items, score: :created_at
end

# Clean up
begin
  existing = Familia.dbclient.keys('integration_item:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
IntegrationItem.instances.clear
IntegrationItem.email_lookup.clear
IntegrationItem.all_integration_items.clear

## Create three objects with participation and index data
@i1 = IntegrationItem.new(iid: 'int-1', name: 'Alpha', email: 'alpha@test.com', created_at: Familia.now.to_f)
@i1.save
IntegrationItem.add_to_all_integration_items(@i1, Familia.now.to_f)
@i2 = IntegrationItem.new(iid: 'int-2', name: 'Beta', email: 'beta@test.com', created_at: Familia.now.to_f)
@i2.save
IntegrationItem.add_to_all_integration_items(@i2, Familia.now.to_f)
@i3 = IntegrationItem.new(iid: 'int-3', name: 'Gamma', email: 'gamma@test.com', created_at: Familia.now.to_f)
@i3.save
IntegrationItem.add_to_all_integration_items(@i3, Familia.now.to_f)
IntegrationItem.instances.size
#=> 3

## Verify clean state before corruption
@report = IntegrationItem.health_check
@report.healthy?
#=> true

## Introduce corruption in instances: remove int-1 from timeline
IntegrationItem.instances.remove('int-1')
IntegrationItem.instances.member?('int-1')
#=> false

## Introduce corruption in unique index: add stale entry for non-existent object
IntegrationItem.dbclient.hset(IntegrationItem.email_lookup.dbkey, 'stale@test.com', '"int-999"')
IntegrationItem.audit_unique_indexes.first[:stale].size
#=> 1

## Introduce corruption in participation: delete int-3 key but leave in collection
Familia.dbclient.del(@i3.dbkey)
IntegrationItem.all_integration_items.membersraw.include?('int-3')
#=> true

## Verify health_check detects all three corruption dimensions
@report = IntegrationItem.health_check
@report.healthy?
#=> false

## Run repair_all! to fix all dimensions
@result = IntegrationItem.repair_all!
@result.is_a?(Hash)
#=> true

## repair_all! returns an AuditReport in the report key
@result[:report].class.name
#=> "Familia::Horreum::AuditReport"

## Instances repair: missing entry was added back
@result[:instances][:missing_added]
#=> 1

## Instances repair: int-1 is back in timeline
IntegrationItem.instances.member?('int-1')
#=> true

## Indexes repair: stale index was rebuilt
@result[:indexes][:rebuilt]
#=> [:email_lookup]

## Indexes repair: stale entry is gone after rebuild
IntegrationItem.audit_unique_indexes.first[:stale].size
#=> 0

## Participations repair: stale member was removed
@result[:participations][:stale_removed]
#=> 1

## Participations repair: int-3 is no longer in collection
IntegrationItem.all_integration_items.membersraw.include?('int-3')
#=> false

## Participations repair: valid members remain
IntegrationItem.all_integration_items.membersraw.include?('int-1')
#=> true

## Participations repair: second valid member remains
IntegrationItem.all_integration_items.membersraw.include?('int-2')
#=> true

## After repair_all!, health check is clean (excluding phantom from int-3 deletion)
@post_report = IntegrationItem.health_check
@post_instances = @post_report.instances
@post_instances[:missing].empty?
#=> true

## After repair_all!, indexes are clean
@post_report.unique_indexes.all? { |idx| idx[:stale].empty? && idx[:missing].empty? }
#=> true

## After repair_all!, participations are clean
@post_report.participations.all? { |p| p[:stale_members].empty? }
#=> true

## repair_all! on already-repaired state is a no-op for instances
@noop = IntegrationItem.repair_all!
@noop[:instances][:missing_added]
#=> 0

## repair_all! on already-repaired state is a no-op for indexes
@noop[:indexes][:rebuilt]
#=> []

## repair_all! on already-repaired state is a no-op for participations
@noop[:participations][:stale_removed]
#=> 0

# Teardown
begin
  existing = Familia.dbclient.keys('integration_item:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
IntegrationItem.instances.clear
IntegrationItem.email_lookup.clear
IntegrationItem.all_integration_items.clear
