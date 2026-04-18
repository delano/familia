# try/audit/m3_multi_index_stub_try.rb
#
# frozen_string_literal: true

# M3: audit_multi_indexes behavior
#
# Covers the real class-level multi-index audit implementation plus the
# still-stubbed instance-scoped path. Class-level indexes are audited in
# three phases (stale members, missing objects, orphaned buckets) while
# instance-scoped indexes return status: :not_implemented with a clearer
# diagnostic message.

require_relative '../support/helpers/test_helpers'

class M3PlainModel < Familia::Horreum
  identifier_field :m3id
  field :m3id
  field :name
end

class M3ScopeTarget < Familia::Horreum
  feature :relationships

  identifier_field :tid
  field :tid
  field :name
end

class M3ScopedModel < Familia::Horreum
  feature :relationships

  identifier_field :sid
  field :sid
  field :category
  field :name

  multi_index :category, :category_index, within: M3ScopeTarget
end

class M3ClassScopedModel < Familia::Horreum
  feature :relationships

  identifier_field :csid
  field :csid
  field :role
  field :name

  multi_index :role, :role_index
end

# Clean up
begin
  [M3PlainModel, M3ScopeTarget, M3ScopedModel, M3ClassScopedModel].each do |klass|
    existing = Familia.dbclient.keys("#{klass.prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
  end
rescue => e
  # Ignore cleanup errors
end
M3PlainModel.instances.clear
M3ScopeTarget.instances.clear
M3ScopedModel.instances.clear
M3ClassScopedModel.instances.clear

## audit_multi_indexes on class without indexes returns empty array
M3PlainModel.audit_multi_indexes
#=> []

## audit_multi_indexes on class without indexes is still an Array
M3PlainModel.audit_multi_indexes.is_a?(Array)
#=> true

## health_check multi_indexes field is an array
@report = M3PlainModel.health_check
@report.multi_indexes.is_a?(Array)
#=> true

## health_check still reports healthy when no multi-indexes defined
@report.healthy?
#=> true

## Instance-scoped multi-index audit returns one result
@results = M3ScopedModel.audit_multi_indexes
@results.size
#=> 1

## Instance-scoped multi-index result has index_name
@results.first[:index_name]
#=> :category_index

## Instance-scoped multi-index result includes status: :not_implemented
@results.first[:status]
#=> :not_implemented

## Instance-scoped multi-index result has empty stale_members
@results.first[:stale_members]
#=> []

## Instance-scoped multi-index result has empty orphaned_keys
@results.first[:orphaned_keys]
#=> []

## Instance-scoped multi-index result has a missing field too
@results.first[:missing]
#=> []

## health_check with instance-scoped multi-index returns AuditReport
@scoped_report = M3ScopedModel.health_check
@scoped_report.class.name
#=> "Familia::Horreum::AuditReport"

## health_check includes multi_indexes with status marker
@scoped_report.multi_indexes.any? { |idx| idx[:status] == :not_implemented }
#=> true

## health_check is still healthy with not_implemented stub (empty collections)
@scoped_report.healthy?
#=> true

## health_check complete? is false when a stubbed index exists
@scoped_report.complete?
#=> false

## Plain-model health check is complete when audit_collections is enabled
M3PlainModel.health_check(audit_collections: true, check_cross_refs: true).complete?
#=> true

## Class-scoped multi-index audit returns one result on healthy baseline
M3ClassScopedModel.instances.clear
existing = Familia.dbclient.keys("#{M3ClassScopedModel.prefix}:*")
Familia.dbclient.del(*existing) if existing.any?
@cs1 = M3ClassScopedModel.new(csid: 'csid-1', role: 'admin', name: 'One')
@cs1.save
@cs2 = M3ClassScopedModel.new(csid: 'csid-2', role: 'admin', name: 'Two')
@cs2.save
@cs3 = M3ClassScopedModel.new(csid: 'csid-3', role: 'member', name: 'Three')
@cs3.save
@class_results = M3ClassScopedModel.audit_multi_indexes
@class_results.size
#=> 1

## Healthy baseline: status is :ok
@class_results.first[:status]
#=> :ok

## Healthy baseline: stale_members is empty
@class_results.first[:stale_members]
#=> []

## Healthy baseline: missing is empty
@class_results.first[:missing]
#=> []

## Healthy baseline: orphaned_keys is empty
@class_results.first[:orphaned_keys]
#=> []

## Healthy baseline: index_name is correct
@class_results.first[:index_name]
#=> :role_index

## Stale (object_missing): delete hash key directly
M3ClassScopedModel.dbclient.del(M3ClassScopedModel.dbkey('csid-2'))
@stale_result = M3ClassScopedModel.audit_multi_indexes.first
@stale_result[:stale_members].any? { |m| m[:indexed_id] == 'csid-2' && m[:reason] == :object_missing }
#=> true

## Stale (object_missing): status transitions to :issues_found
@stale_result[:status]
#=> :issues_found

## Stale (value_mismatch): mutate field directly via HSET
@cs2.save
M3ClassScopedModel.dbclient.hset(M3ClassScopedModel.dbkey('csid-1'), 'role', '"manager"')
@mm_result = M3ClassScopedModel.audit_multi_indexes.first
@mismatch = @mm_result[:stale_members].find { |m| m[:indexed_id] == 'csid-1' }
@mismatch[:reason]
#=> :value_mismatch

## Stale (value_mismatch): field_value reflects old bucket
@mismatch[:field_value]
#=> "admin"

## Stale (value_mismatch): current_value reflects new field value
@mismatch[:current_value]
#=> "manager"

## Stale (value_mismatch): missing entry added for new field value bucket
@mm_result[:missing].any? { |m| m[:identifier] == 'csid-1' && m[:field_value] == 'manager' }
#=> true

## Missing: create an object whose field value bucket does not exist
@cs1.role = 'admin'
@cs1.save
@raw_id = 'csid-raw-1'
M3ClassScopedModel.dbclient.hset(
  M3ClassScopedModel.dbkey(@raw_id),
  'csid', '"csid-raw-1"',
  'role', '"observer"',
  'name', '"Raw"',
)
@missing_result = M3ClassScopedModel.audit_multi_indexes.first
@missing_result[:missing].any? { |m| m[:identifier] == 'csid-raw-1' && m[:field_value] == 'observer' }
#=> true

## Missing: status is :issues_found
@missing_result[:status]
#=> :issues_found

## Orphaned: manually SADD a bucket that no object holds
M3ClassScopedModel.dbclient.del(M3ClassScopedModel.dbkey('csid-raw-1'))
@orphan_key = "#{M3ClassScopedModel.prefix}:role_index:ghost"
M3ClassScopedModel.dbclient.sadd(@orphan_key, '"phantom"')
@orphan_result = M3ClassScopedModel.audit_multi_indexes.first
@orphan_result[:orphaned_keys].any? { |o| o[:field_value] == 'ghost' && o[:key] == @orphan_key }
#=> true

## Orphaned: status is :issues_found
@orphan_result[:status]
#=> :issues_found

## Nil field value is skipped gracefully
M3ClassScopedModel.dbclient.del(@orphan_key)
@cs_nil = M3ClassScopedModel.new(csid: 'csid-nil', role: nil, name: 'Nil')
@cs_nil.save
@nil_result = M3ClassScopedModel.audit_multi_indexes.first
@nil_result[:missing].any? { |m| m[:identifier] == 'csid-nil' }
#=> false

## Nil field value does not produce stale members either
@nil_result[:stale_members].any? { |m| m[:indexed_id] == 'csid-nil' }
#=> false

## Missing entries on class-level multi-index make the report unhealthy and surface in to_h/to_s
# Inline setup: fresh model and fresh state so the assertion does not depend on prior testcases.
class M3MissingFlagModel < Familia::Horreum
  feature :relationships
  identifier_field :mfid
  field :mfid
  field :role
  field :name
  multi_index :role, :role_index
end
M3MissingFlagModel.instances.clear
existing_mfm = Familia.dbclient.keys("#{M3MissingFlagModel.prefix}:*")
Familia.dbclient.del(*existing_mfm) if existing_mfm.any?
@mf1 = M3MissingFlagModel.new(mfid: 'mf-1', role: 'admin', name: 'One')
@mf1.save
# Inject a live object via direct HSET, bypassing the index-update write path.
M3MissingFlagModel.dbclient.hset(
  M3MissingFlagModel.dbkey('mf-raw'),
  'mfid', '"mf-raw"',
  'role', '"observer"',
  'name', '"Raw"',
)
@mf_report = M3MissingFlagModel.health_check
[@mf_report.healthy?,
 @mf_report.to_h[:multi_indexes].first[:missing],
 @mf_report.to_s.include?('missing=1')]
#=> [false, 1, true]

# Cleanup for the inline test
existing_mfm_cleanup = Familia.dbclient.keys("#{M3MissingFlagModel.prefix}:*")
Familia.dbclient.del(*existing_mfm_cleanup) if existing_mfm_cleanup.any?
M3MissingFlagModel.instances.clear

# Teardown
begin
  [M3PlainModel, M3ScopeTarget, M3ScopedModel, M3ClassScopedModel].each do |klass|
    existing = Familia.dbclient.keys("#{klass.prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
  end
rescue => e
  # Ignore cleanup errors
end
M3PlainModel.instances.clear
M3ScopeTarget.instances.clear
M3ScopedModel.instances.clear
M3ClassScopedModel.instances.clear
