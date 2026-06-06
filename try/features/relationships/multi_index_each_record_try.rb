# try/features/relationships/multi_index_each_record_try.rb
#
# frozen_string_literal: true

# Tests for issue #301: multi_index UnsortedSets were created without
# `class:` or `reference:` options, so identifiers were JSON-encoded
# (e.g. "u1" stored as "\"u1\""). This broke:
#   - each_record (requires @opts[:class] to load records)
#   - member?(object) (Familia objects bypass JSON encoding in
#     serialize_value, producing a raw string that doesn't match
#     the JSON-encoded value in Redis)
#
# The fix adds `class: indexed_class, reference: true` to both
# instance-scoped and class-level multi_index factory methods.

require_relative '../../support/helpers/test_helpers'

class MIERCustomer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid
  field :role

  multi_index :role, :role_index

  class_sorted_set :instances, reference: true
end

class MIERCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id

  class_sorted_set :instances, reference: true
end

class MIEREmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :department

  multi_index :department, :dept_index, within: MIERCompany
  participates_in MIERCompany, :employees, score: :emp_id

  class_sorted_set :instances, reference: true
end

# Setup - class-level
[MIERCustomer, MIEREmployee, MIERCompany].each do |klass|
  existing = Familia.dbclient.keys("#{klass.prefix}:*")
  Familia.dbclient.del(*existing) if existing.any?
  klass.instances.clear if klass.respond_to?(:instances)
end

@c1 = MIERCustomer.new(custid: 'c1', role: 'admin')
@c1.save
@c2 = MIERCustomer.new(custid: 'c2', role: 'admin')
@c2.save
@c3 = MIERCustomer.new(custid: 'c3', role: 'user')
@c3.save

# Setup - instance-scoped
@company = MIERCompany.new(company_id: 'co1')
@company.save
@e1 = MIEREmployee.new(emp_id: 'e1', department: 'eng')
@e1.save
@e1.add_to_mier_company_employees(@company)
@e1.add_to_mier_company_dept_index(@company)
@e2 = MIEREmployee.new(emp_id: 'e2', department: 'eng')
@e2.save
@e2.add_to_mier_company_employees(@company)
@e2.add_to_mier_company_dept_index(@company)
@e3 = MIEREmployee.new(emp_id: 'e3', department: 'sales')
@e3.save
@e3.add_to_mier_company_employees(@company)
@e3.add_to_mier_company_dept_index(@company)

# ============================================================
# Class-level multi_index UnsortedSet is a proper reference type
# ============================================================

## Class-level multi_index UnsortedSet carries the indexed class
MIERCustomer.role_index_for('admin').opts[:class]
#=> MIERCustomer

## Class-level multi_index UnsortedSet is a reference type
MIERCustomer.role_index_for('admin').opts[:reference]
#=> true

## Stored values are raw identifiers (not JSON-encoded)
raw = MIERCustomer.dbclient.smembers(MIERCustomer.role_index_for('admin').dbkey)
raw.sort
#=> ["c1", "c2"]

# ============================================================
# each_record on class-level multi_index (issue #301)
# ============================================================

## each_record yields Horreum records
records = []
MIERCustomer.role_index_for('admin').each_record { |r| records << r }
records.all? { |r| r.is_a?(MIERCustomer) }
#=> true

## each_record yields every indexed record
records = []
MIERCustomer.role_index_for('admin').each_record { |r| records << r }
records.map(&:custid).sort
#=> ["c1", "c2"]

## each_record returns an Enumerator when no block is given
MIERCustomer.role_index_for('admin').each_record.class
#=> Enumerator

## each_record Enumerator composes with Enumerable
MIERCustomer.role_index_for('admin').each_record.map(&:custid).sort
#=> ["c1", "c2"]

## each_record honors batch_size
records = []
MIERCustomer.role_index_for('admin').each_record(batch_size: 1) { |r| records << r }
records.map(&:custid).sort
#=> ["c1", "c2"]

## each_record skips ghost entries (stale identifier in set)
admin_set = MIERCustomer.role_index_for('admin')
admin_set.add('c-ghost')
records = []
admin_set.each_record { |r| records << r }
result = records.map(&:custid).sort
admin_set.remove('c-ghost')
result
#=> ["c1", "c2"]

## each_record on a different field value
records = []
MIERCustomer.role_index_for('user').each_record { |r| records << r }
records.map(&:custid)
#=> ["c3"]

# ============================================================
# member?(object) on class-level multi_index (issue #301)
# ============================================================

## member? with a Familia object returns true when present
MIERCustomer.role_index_for('admin').member?(@c1)
#=> true

## member? with a Familia object returns false when absent
MIERCustomer.role_index_for('user').member?(@c1)
#=> false

## member? with a string identifier returns true when present
MIERCustomer.role_index_for('admin').member?('c1')
#=> true

## member? with a string identifier returns false when absent
MIERCustomer.role_index_for('admin').member?('nonexistent')
#=> false

# ============================================================
# Instance-scoped multi_index
# ============================================================

## Instance-scoped multi_index UnsortedSet carries the indexed class
@company.dept_index_for('eng').opts[:class]
#=> MIEREmployee

## Instance-scoped multi_index UnsortedSet is a reference type
@company.dept_index_for('eng').opts[:reference]
#=> true

## Instance-scoped stored values are raw identifiers
raw = Familia.dbclient.smembers(@company.dept_index_for('eng').dbkey)
raw.sort
#=> ["e1", "e2"]

## each_record on instance-scoped multi_index yields indexed employees
records = []
@company.dept_index_for('eng').each_record { |r| records << r }
records.map(&:emp_id).sort
#=> ["e1", "e2"]

## each_record on different field value
records = []
@company.dept_index_for('sales').each_record { |r| records << r }
records.map(&:emp_id)
#=> ["e3"]

## member? with Familia object on instance-scoped multi_index
@company.dept_index_for('eng').member?(@e1)
#=> true

## member? with absent object on instance-scoped multi_index
@company.dept_index_for('sales').member?(@e1)
#=> false

## member? with string identifier on instance-scoped multi_index
@company.dept_index_for('eng').member?('e2')
#=> true

# Teardown
[MIERCustomer, MIEREmployee, MIERCompany].each do |klass|
  existing = Familia.dbclient.keys("#{klass.prefix}:*")
  Familia.dbclient.del(*existing) if existing.any?
  klass.instances.clear if klass.respond_to?(:instances)
end
