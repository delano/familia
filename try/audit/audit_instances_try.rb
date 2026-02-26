# try/audit/audit_instances_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class AuditPlainModel < Familia::Horreum
  identifier_field :pid
  field :pid
  field :name
end

# Clean up any leftover test data
begin
  existing = Familia.dbclient.keys('audit_plain_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditPlainModel.instances.clear

## audit_instances on clean state returns empty arrays
@result = AuditPlainModel.audit_instances
@result[:phantoms]
#=> []

## audit_instances clean state has no missing entries
@result[:missing]
#=> []

## audit_instances clean state has zero counts
@result[:count_timeline]
#=> 0

## Create objects for audit
@obj1 = AuditPlainModel.new(pid: 'audit-1', name: 'Alice')
@obj1.save
@obj2 = AuditPlainModel.new(pid: 'audit-2', name: 'Bob')
@obj2.save
@obj3 = AuditPlainModel.new(pid: 'audit-3', name: 'Charlie')
@obj3.save
AuditPlainModel.audit_instances[:count_timeline]
#=> 3

## audit_instances reports matching scan count
AuditPlainModel.audit_instances[:count_scan]
#=> 3

## Consistent state has no phantoms
AuditPlainModel.audit_instances[:phantoms].size
#=> 0

## Consistent state has no missing
AuditPlainModel.audit_instances[:missing].size
#=> 0

## Phantom detection: delete key but leave timeline entry
Familia.dbclient.del(@obj1.dbkey)
@result = AuditPlainModel.audit_instances
@result[:phantoms]
#=> ['audit-1']

## Phantom detection: scan count is lower than timeline
@result[:count_scan]
#=> 2

## Phantom detection: timeline count stays at 3
@result[:count_timeline]
#=> 3

## Missing detection: remove from timeline but leave key
@obj1_restored = AuditPlainModel.new(pid: 'audit-1', name: 'Alice')
@obj1_restored.save
AuditPlainModel.instances.remove('audit-2')
@result = AuditPlainModel.audit_instances
@result[:missing]
#=> ['audit-2']

## Missing detection: timeline count is lower
@result[:count_timeline]
#=> 2

## Missing detection: scan count is higher
@result[:count_scan]
#=> 3

## Both phantoms and missing detected simultaneously
Familia.dbclient.del(@obj3.dbkey)
@result = AuditPlainModel.audit_instances
@result[:phantoms].sort
#=> ['audit-3']

## Both detected: missing is still audit-2
@result[:missing].sort
#=> ['audit-2']

## audit_instances accepts batch_size parameter
@result = AuditPlainModel.audit_instances(batch_size: 1)
@result[:phantoms].sort
#=> ['audit-3']

## audit_instances accepts progress callback
@progress = []
AuditPlainModel.audit_instances { |p| @progress << p }
@progress.any? { |p| p[:phase] == :timeline_collected }
#=> true

## Progress callback reports scanning phase
@progress.any? { |p| p[:phase] == :scanning }
#=> true

# Teardown
begin
  existing = Familia.dbclient.keys('audit_plain_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditPlainModel.instances.clear
