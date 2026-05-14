# try/audit/audit_instance_scoped_multi_index_try.rb
#
# frozen_string_literal: true

# Instance-scoped multi-index audit
#
# Covers the previously-stubbed path. Validates discovery of buckets
# across scope instances, detection of stale members (object_missing
# and value_mismatch), orphaned buckets (scope_missing and
# field_value_unheld), and missing entries detected via the
# participation relationship from the indexed class to the scope class.

require_relative '../support/helpers/test_helpers'

class ::ISMICompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name

  class_sorted_set :instances, reference: true
end

class ::ISMIEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :department
  field :name

  multi_index :department, :dept_index, within: ISMICompany
  participates_in ISMICompany, :employees, score: :emp_id

  class_sorted_set :instances, reference: true
end

def ismi_reset!
  [ISMICompany, ISMIEmployee].each do |klass|
    existing = Familia.dbclient.keys("#{klass.prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
    klass.instances.clear if klass.respond_to?(:instances)
  end
end

def ismi_seed!
  ismi_reset!
  @c1 = ISMICompany.new(company_id: 'c-1', name: 'Acme')
  @c1.save
  @c2 = ISMICompany.new(company_id: 'c-2', name: 'Globex')
  @c2.save

  @e1 = ISMIEmployee.new(emp_id: 'e-1', department: 'engineering', name: 'Alice')
  @e1.save
  @e1.add_to_ismi_company_employees(@c1)
  @e1.add_to_ismi_company_dept_index(@c1)

  @e2 = ISMIEmployee.new(emp_id: 'e-2', department: 'engineering', name: 'Bob')
  @e2.save
  @e2.add_to_ismi_company_employees(@c1)
  @e2.add_to_ismi_company_dept_index(@c1)

  @e3 = ISMIEmployee.new(emp_id: 'e-3', department: 'sales', name: 'Carla')
  @e3.save
  @e3.add_to_ismi_company_employees(@c2)
  @e3.add_to_ismi_company_dept_index(@c2)
end

ismi_reset!

## Empty state: audit returns a single result for the declared index
@empty = ISMIEmployee.audit_multi_indexes
@empty.size
#=> 1

## Empty state: status is :ok
@empty.first[:status]
#=> :ok

## Empty state: stale_members, missing, orphaned_keys all empty
[@empty.first[:stale_members], @empty.first[:missing], @empty.first[:orphaned_keys]]
#=> [[], [], []]

## Healthy baseline: status :ok
ismi_seed!
ISMIEmployee.audit_multi_indexes.first[:status]
#=> :ok

## Healthy baseline: no stale members
ismi_seed!
ISMIEmployee.audit_multi_indexes.first[:stale_members]
#=> []

## Healthy baseline: no missing
ismi_seed!
ISMIEmployee.audit_multi_indexes.first[:missing]
#=> []

## Healthy baseline: no orphaned keys
ismi_seed!
ISMIEmployee.audit_multi_indexes.first[:orphaned_keys]
#=> []

## Stale (object_missing): delete employee hash key directly
ismi_seed!
ISMIEmployee.dbclient.del(ISMIEmployee.dbkey('e-1'))
@result = ISMIEmployee.audit_multi_indexes.first
@result[:stale_members].any? { |m| m[:indexed_id] == 'e-1' && m[:reason] == :object_missing }
#=> true

## Stale (object_missing): scope_id is reported on the stale entry
ismi_seed!
ISMIEmployee.dbclient.del(ISMIEmployee.dbkey('e-1'))
@result = ISMIEmployee.audit_multi_indexes.first
@result[:stale_members].find { |m| m[:indexed_id] == 'e-1' }[:scope_id]
#=> "c-1"

## Stale (object_missing): status transitions to :issues_found
ismi_seed!
ISMIEmployee.dbclient.del(ISMIEmployee.dbkey('e-1'))
ISMIEmployee.audit_multi_indexes.first[:status]
#=> :issues_found

## Stale (value_mismatch): mutate field via direct HSET
ismi_seed!
ISMIEmployee.dbclient.hset(ISMIEmployee.dbkey('e-1'), 'department', '"marketing"')
@result = ISMIEmployee.audit_multi_indexes.first
@mm = @result[:stale_members].find { |m| m[:indexed_id] == 'e-1' }
[@mm[:reason], @mm[:field_value], @mm[:current_value]]
#=> [:value_mismatch, "engineering", "marketing"]

## Stale (value_mismatch): missing entry added for the new bucket
ismi_seed!
ISMIEmployee.dbclient.hset(ISMIEmployee.dbkey('e-1'), 'department', '"marketing"')
@result = ISMIEmployee.audit_multi_indexes.first
@result[:missing].any? { |m| m[:identifier] == 'e-1' && m[:field_value] == 'marketing' }
#=> true

## Missing: object exists in participation but not in the bucket
ismi_seed!
# Inject an employee via direct HSET so the index-update mutation path is bypassed
ISMIEmployee.dbclient.hset(
  ISMIEmployee.dbkey('e-raw'),
  'emp_id', '"e-raw"',
  'department', '"finance"',
  'name', '"Raw"',
)
# Participate raw employee with company c1 (bypassing the index path on save).
# Use the instance dbkey directly (suffix=:employees) so the collection key
# is "ismi_company:c-1:employees" rather than "...:object:employees".
ISMIEmployee.dbclient.zadd(
  ISMICompany.dbkey('c-1', :employees),
  Familia.now,
  'e-raw',
)
@result = ISMIEmployee.audit_multi_indexes.first
@hit = @result[:missing].find { |m| m[:identifier] == 'e-raw' }
[@hit && @hit[:field_value], @hit && @hit[:scope_id]]
#=> ["finance", "c-1"]

## Orphaned: scope instance destroyed but bucket key lingers
ismi_seed!
# Drop the company hash directly; bucket key under that company is now orphaned
ISMICompany.dbclient.del(ISMICompany.dbkey('c-1'))
@result = ISMIEmployee.audit_multi_indexes.first
@orphans = @result[:orphaned_keys].select { |o| o[:scope_id] == 'c-1' && o[:reason] == :scope_missing }
@orphans.size >= 1
#=> true

## Orphaned: scope_missing reason on the orphan entry
ismi_seed!
ISMICompany.dbclient.del(ISMICompany.dbkey('c-1'))
@result = ISMIEmployee.audit_multi_indexes.first
@result[:orphaned_keys].first[:reason]
#=> :scope_missing

## Orphaned (field_value_unheld): bucket whose field_value no live participant holds
ismi_seed!
# Manually create a bucket under c-1 for a department no employee has.
# Use the instance dbkey directly so the key is
# "ismi_company:c-1:dept_index:legal" with no :object segment.
ISMIEmployee.dbclient.sadd(
  ISMICompany.dbkey('c-1', 'dept_index:legal'),
  '"e-1"',
)
@result = ISMIEmployee.audit_multi_indexes.first
@unheld = @result[:orphaned_keys].find { |o| o[:field_value] == 'legal' && o[:scope_id] == 'c-1' }
@unheld[:reason]
#=> :field_value_unheld

## Healthy baseline: missing_status is :ok when participation exists
ismi_seed!
ISMIEmployee.audit_multi_indexes.first[:missing_status]
#=> nil

# Teardown
ismi_reset!
