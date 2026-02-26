# try/audit/repair_instances_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class RepairModel < Familia::Horreum
  identifier_field :rid
  field :rid
  field :name
  field :updated
  field :created
end

# Clean up
begin
  existing = Familia.dbclient.keys('repair_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairModel.instances.clear

## repair_instances! exists as class method
RepairModel.respond_to?(:repair_instances!)
#=> true

## Create test objects
@r1 = RepairModel.new(rid: 'rep-1', name: 'One')
@r1.save
@r2 = RepairModel.new(rid: 'rep-2', name: 'Two')
@r2.save
@r3 = RepairModel.new(rid: 'rep-3', name: 'Three')
@r3.save
RepairModel.instances.size
#=> 3

## Introduce phantom: delete key, leave timeline entry
Familia.dbclient.del(@r1.dbkey)
RepairModel.audit_instances[:phantoms]
#=> ['rep-1']

## repair_instances! removes phantom
@result = RepairModel.repair_instances!
@result[:phantoms_removed]
#=> 1

## After repair, phantom is gone from timeline
RepairModel.instances.member?('rep-1')
#=> false

## After repair, timeline count is correct
RepairModel.instances.size
#=> 2

## Introduce missing: remove from timeline, leave key
RepairModel.instances.remove('rep-2')
RepairModel.audit_instances[:missing]
#=> ['rep-2']

## repair_instances! adds missing entry
@result = RepairModel.repair_instances!
@result[:missing_added]
#=> 1

## After repair, missing entry is in timeline
RepairModel.instances.member?('rep-2')
#=> true

## After repair, timeline is consistent
@audit = RepairModel.audit_instances
@audit[:phantoms].empty? && @audit[:missing].empty?
#=> true

## repair_instances! accepts pre-computed audit result
Familia.dbclient.del(@r3.dbkey)
@audit = RepairModel.audit_instances
@result = RepairModel.repair_instances!(@audit)
@result[:phantoms_removed]
#=> 1

## After full repair cycle, state is clean
@audit = RepairModel.audit_instances
@audit[:phantoms].size + @audit[:missing].size
#=> 0

# Teardown
begin
  existing = Familia.dbclient.keys('repair_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairModel.instances.clear
