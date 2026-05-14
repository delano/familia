# try/audit/repair_all_robustness_try.rb
#
# frozen_string_literal: true

# repair_all! robustness:
#  - per-stage exception isolation
#  - aggregate :status / :errors return shape
#  - opt-in :verify post-audit
#  - multi-index repair coverage (class-level and instance-scoped)

require_relative '../support/helpers/test_helpers'

class RARoleModel < Familia::Horreum
  feature :relationships

  identifier_field :rid
  field :rid
  field :role
  field :name

  multi_index :role, :role_index

  class_sorted_set :instances, reference: true
end

class RARoleCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name

  class_sorted_set :instances, reference: true
end

class RARoleEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :department
  field :name

  multi_index :department, :dept_index, within: RARoleCompany
  participates_in RARoleCompany, :employees, score: :emp_id

  class_sorted_set :instances, reference: true
end

def rar_reset!
  [RARoleModel, RARoleCompany, RARoleEmployee].each do |klass|
    existing = Familia.dbclient.keys("#{klass.prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
    klass.instances.clear if klass.respond_to?(:instances)
  end
end

rar_reset!

## repair_all! returns :status => :ok on a clean model
@r1 = RARoleModel.new(rid: 'r-1', role: 'admin', name: 'One')
@r1.save
@result_clean = RARoleModel.repair_all!
@result_clean[:status]
#=> :ok

## repair_all! returns an empty :errors hash on a clean model
@result_clean[:errors]
#=> {}

## repair_all! has a :multi_indexes stage entry
@result_clean[:multi_indexes].is_a?(Hash)
#=> true

## repair_all! :verify => true exposes :post_audit and :verified
@result_verified = RARoleModel.repair_all!(verify: true)
[@result_verified[:verified], @result_verified[:post_audit].class.name]
#=> [true, "Familia::Horreum::AuditReport"]

## Class-level multi-index rebuild: drift in role_index is fixed by repair_all!
# Inject a raw object so the index-update path is bypassed
RARoleModel.dbclient.hset(
  RARoleModel.dbkey('r-raw'),
  'rid', '"r-raw"',
  'role', '"observer"',
  'name', '"Raw"',
)
@pre_audit = RARoleModel.audit_multi_indexes.first
@result_fixed = RARoleModel.repair_all!(verify: true)
[@pre_audit[:missing].any? { |m| m[:identifier] == 'r-raw' },
 @result_fixed[:multi_indexes][:rebuilt].include?(:role_index),
 @result_fixed[:verified]]
#=> [true, true, true]

## Instance-scoped multi-index rebuild: drift via raw participation is fixed
rar_reset!
@c1 = RARoleCompany.new(company_id: 'c-1', name: 'Acme')
@c1.save
@e1 = RARoleEmployee.new(emp_id: 'e-1', department: 'engineering', name: 'Alice')
@e1.save
@e1.add_to_ra_role_company_employees(@c1)
@e1.add_to_ra_role_company_dept_index(@c1)
# Inject a raw participant whose department bucket does not exist
RARoleEmployee.dbclient.hset(
  RARoleEmployee.dbkey('e-raw'),
  'emp_id', '"e-raw"',
  'department', '"sales"',
  'name', '"Raw"',
)
RARoleEmployee.dbclient.zadd(
  RARoleCompany.dbkey('c-1', :employees),
  Familia.now,
  'e-raw',
)
@pre = RARoleEmployee.audit_multi_indexes.first
@out = RARoleEmployee.repair_all!(verify: true)
[@pre[:missing].any? { |m| m[:identifier] == 'e-raw' && m[:scope_id] == 'c-1' },
 @out[:multi_indexes][:rebuilt_per_scope].any? { |r| r[:index_name] == :dept_index && r[:scopes_rebuilt] >= 1 },
 @out[:verified]]
#=> [true, true, true]

## repair_all! isolates per-stage failures into :errors and continues
rar_reset!
@r2 = RARoleModel.new(rid: 'r-2', role: 'admin', name: 'Two')
@r2.save

# Stub repair_indexes! to raise; other stages should still run.
class << RARoleModel
  alias_method :_orig_repair_indexes!, :repair_indexes!
  def repair_indexes!(*)
    raise StandardError, 'simulated index failure'
  end
end

@out = RARoleModel.repair_all!
[@out[:status],
 @out[:errors].keys,
 @out[:instances].is_a?(Hash),
 @out[:participations].is_a?(Hash)]
#=> [:partial_failure, [:indexes], true, true]

# Restore
class << RARoleModel
  alias_method :repair_indexes!, :_orig_repair_indexes!
  remove_method :_orig_repair_indexes!
end

# Teardown
rar_reset!
