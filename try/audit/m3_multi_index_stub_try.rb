# try/audit/m3_multi_index_stub_try.rb
#
# frozen_string_literal: true

# M3: audit_multi_indexes stub marker
#
# Verifies that audit_multi_indexes returns results with
# status: :not_implemented and that health_check reflects it.
# Tests both class-scoped multi-indexes (within: :class) and
# instance-scoped multi-indexes (within: SomeClass).

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

  # Instance-scoped multi-index (within a non-:class scope)
  # triggers the not_implemented code path in audit_single_multi_index
  multi_index :category, :category_index, within: M3ScopeTarget
end

class M3ClassScopedModel < Familia::Horreum
  feature :relationships

  identifier_field :csid
  field :csid
  field :role
  field :name

  # Class-scoped multi-index (within: :class is default)
  # triggers the early-return code path (no status key)
  multi_index :role, :role_index
end

# Clean up
begin
  ['m3_plain_model', 'm3_scope_target', 'm3_scoped_model', 'm3_class_scoped_model'].each do |prefix|
    existing = Familia.dbclient.keys("#{prefix}:*")
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

## Class-scoped multi-index audit returns one result
@class_results = M3ClassScopedModel.audit_multi_indexes
@class_results.size
#=> 1

## Class-scoped multi-index result also has status: :not_implemented
# Both class-scoped and instance-scoped paths return the status marker
@class_results.first[:status]
#=> :not_implemented

## Class-scoped multi-index result has empty stale_members
@class_results.first[:stale_members]
#=> []

## health_check with instance-scoped multi-index returns AuditReport
@report = M3ScopedModel.health_check
@report.class.name
#=> "Familia::Horreum::AuditReport"

## health_check includes multi_indexes with status marker
@report.multi_indexes.any? { |idx| idx[:status] == :not_implemented }
#=> true

## health_check is still healthy with not_implemented stub (empty collections)
@report.healthy?
#=> true

## health_check to_h includes multi_indexes summary
@h = @report.to_h
@h[:multi_indexes].is_a?(Array) && @h[:multi_indexes].size == 1
#=> true

## health_check to_s includes multi_index information
@report.to_s.include?('multi_index')
#=> true

## health_check to_s shows not_implemented for stubbed multi-index
@report.to_s.include?('not_implemented')
#=> true

## health_check complete? returns false with not_implemented stub
@report.complete?
#=> false

## health_check on class with no multi-indexes is complete
@plain_report = M3PlainModel.health_check
@plain_report.complete?
#=> true

## health_check to_h includes complete key
@report.to_h[:complete]
#=> false

## health_check to_h multi_indexes entry includes status
@report.to_h[:multi_indexes].first[:status]
#=> :not_implemented

# Teardown
begin
  ['m3_plain_model', 'm3_scope_target', 'm3_scoped_model', 'm3_class_scoped_model'].each do |prefix|
    existing = Familia.dbclient.keys("#{prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
  end
rescue => e
  # Ignore cleanup errors
end
M3PlainModel.instances.clear
M3ScopeTarget.instances.clear
M3ScopedModel.instances.clear
M3ClassScopedModel.instances.clear
