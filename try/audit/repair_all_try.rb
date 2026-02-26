# try/audit/repair_all_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class RepairAllModel < Familia::Horreum
  identifier_field :raid
  field :raid
  field :name
end

# Clean up
begin
  existing = Familia.dbclient.keys('repair_all_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairAllModel.instances.clear

## repair_all! exists as class method
RepairAllModel.respond_to?(:repair_all!)
#=> true

## Create test objects
@ra1 = RepairAllModel.new(raid: 'ra-1', name: 'One')
@ra1.save
@ra2 = RepairAllModel.new(raid: 'ra-2', name: 'Two')
@ra2.save
@ra3 = RepairAllModel.new(raid: 'ra-3', name: 'Three')
@ra3.save
RepairAllModel.instances.size
#=> 3

## Introduce phantom and missing simultaneously
Familia.dbclient.del(@ra1.dbkey)
RepairAllModel.instances.remove('ra-2')
RepairAllModel.audit_instances[:phantoms]
#=> ['ra-1']

## Missing is detected
RepairAllModel.audit_instances[:missing]
#=> ['ra-2']

## repair_all! returns combined results with report
@result = RepairAllModel.repair_all!
@result[:instances][:phantoms_removed]
#=> 1

## repair_all! adds missing entries
@result[:instances][:missing_added]
#=> 1

## repair_all! includes the AuditReport
@result[:report].class.name
#=> "Familia::Horreum::AuditReport"

## After repair_all!, health_check is clean
@report = RepairAllModel.health_check
@report.healthy?
#=> true

## After repair_all!, timeline count matches
@report.instances[:count_timeline]
#=> 2

## After repair_all!, scan count matches
@report.instances[:count_scan]
#=> 2

## repair_all! on already-clean state is a no-op
@result = RepairAllModel.repair_all!
@result[:instances][:phantoms_removed] + @result[:instances][:missing_added]
#=> 0

# Teardown
begin
  existing = Familia.dbclient.keys('repair_all_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairAllModel.instances.clear
