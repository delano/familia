# try/audit/m5_repair_batched_try.rb
#
# frozen_string_literal: true

# M5: repair_instances! batched behavior
#
# Verifies that repair_instances! correctly handles phantom removal
# and missing-entry addition after batching changes. Confirms
# functional correctness is identical to pre-batching behavior.

require_relative '../support/helpers/test_helpers'

class M5RepairModel < Familia::Horreum
  identifier_field :m5id
  field :m5id
  field :name
  field :updated
  field :created
end

# Clean up
begin
  existing = Familia.dbclient.keys('m5_repair_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
M5RepairModel.instances.clear

## Create 5 test objects
@objs = (1..5).map { |i|
  obj = M5RepairModel.new(m5id: "m5-#{i}", name: "Object #{i}", updated: Familia.now.to_f)
  obj.save
  obj
}
M5RepairModel.instances.size
#=> 5

## Introduce multiple phantoms by deleting keys
Familia.dbclient.del(@objs[0].dbkey)
Familia.dbclient.del(@objs[1].dbkey)
@audit = M5RepairModel.audit_instances
@audit[:phantoms].sort
#=> ["m5-1", "m5-2"]

## repair_instances! removes all phantoms in one call
@result = M5RepairModel.repair_instances!
@result[:phantoms_removed]
#=> 2

## After phantom repair, timeline has 3 entries
M5RepairModel.instances.size
#=> 3

## Removed phantoms are no longer in timeline
M5RepairModel.instances.member?('m5-1') || M5RepairModel.instances.member?('m5-2')
#=> false

## Remaining entries are still in timeline
['m5-3', 'm5-4', 'm5-5'].all? { |id| M5RepairModel.instances.member?(id) }
#=> true

## Introduce multiple missing entries by removing from timeline
M5RepairModel.instances.remove('m5-3')
M5RepairModel.instances.remove('m5-4')
@audit = M5RepairModel.audit_instances
@audit[:missing].sort
#=> ["m5-3", "m5-4"]

## repair_instances! adds all missing entries in one call
@result = M5RepairModel.repair_instances!
@result[:missing_added]
#=> 2

## After missing repair, timeline has 3 entries
M5RepairModel.instances.size
#=> 3

## Previously missing entries are now in timeline
M5RepairModel.instances.member?('m5-3') && M5RepairModel.instances.member?('m5-4')
#=> true

## Introduce phantoms and missing simultaneously
Familia.dbclient.del(@objs[2].dbkey)  # m5-3 becomes phantom
M5RepairModel.instances.remove('m5-5')  # m5-5 becomes missing
@audit = M5RepairModel.audit_instances
@audit[:phantoms]
#=> ['m5-3']

## Mixed: missing detected
@audit[:missing]
#=> ['m5-5']

## repair_instances! handles both phantoms and missing together
@result = M5RepairModel.repair_instances!
@result[:phantoms_removed]
#=> 1

## Mixed repair: missing entries added
@result[:missing_added]
#=> 1

## After mixed repair, state is clean
@audit = M5RepairModel.audit_instances
@audit[:phantoms].empty? && @audit[:missing].empty?
#=> true

## After mixed repair, correct entries remain
M5RepairModel.instances.size
#=> 2

## Correct identifiers remain after repair
M5RepairModel.instances.member?('m5-4') && M5RepairModel.instances.member?('m5-5')
#=> true

## repair_instances! accepts pre-computed audit result
M5RepairModel.instances.remove('m5-4')
@pre_audit = M5RepairModel.audit_instances
@result = M5RepairModel.repair_instances!(@pre_audit)
@result[:missing_added]
#=> 1

## repair_instances! on clean state is a no-op
@result = M5RepairModel.repair_instances!
@result[:phantoms_removed] + @result[:missing_added]
#=> 0

## Full cycle: create, corrupt, repair, verify clean
@fresh = M5RepairModel.new(m5id: 'm5-fresh', name: 'Fresh', updated: Familia.now.to_f)
@fresh.save
Familia.dbclient.del(@fresh.dbkey)
M5RepairModel.repair_instances!
@final_audit = M5RepairModel.audit_instances
@final_audit[:phantoms].size + @final_audit[:missing].size
#=> 0

# Teardown
begin
  existing = Familia.dbclient.keys('m5_repair_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
M5RepairModel.instances.clear
