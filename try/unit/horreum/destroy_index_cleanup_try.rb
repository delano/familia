# try/unit/horreum/destroy_index_cleanup_try.rb
#
# frozen_string_literal: true

# Horreum destroy! Class-Level Index Cleanup Tryouts
#
# Reproduces GitHub issue #241: `Horreum#destroy!` removes the object hash,
# related fields, and the entry from the class-level `instances` sorted set,
# but does NOT remove entries from class-level `unique_index` hashes or
# `multi_index` sets. Stale `email_index[value] -> objid` entries persist
# after destroy and cause `RecordExistsError` on the next `create!` with
# the same indexed value.
#
# Scope: class-level indexes only (`within: nil` / `within: :class`).
# Instance-scoped indexes (`within: SomeClass`) are a known limitation
# documented separately -- they are not covered by the #241 fix and
# remain orphaned after destroy!.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Throwaway test class that exercises both class-level unique and
# multi-index mutation paths. Named with the issue number to avoid
# colliding with any existing test fixtures.
class ::Widget241 < Familia::Horreum
  feature :relationships

  identifier_field :objid
  field :objid
  field :name
  field :category

  # Class-level unique index -- stored as a single HashKey mapping
  # name -> objid. Every object's save auto-populates; destroy! should
  # remove the corresponding entry but currently does not (bug #241).
  unique_index :name, :name_index

  # Class-level multi-index -- stored per-value as an UnsortedSet named
  # `category_index:<value>`. Every object's save auto-populates; destroy!
  # should remove the identifier from the per-value set but currently
  # does not (bug #241).
  multi_index :category, :category_index
end

# Start from a clean slate for indexes so previous test runs don't leak.
Familia.dbclient.flushdb

## Class-level unique_index is populated by save
@w1 = Widget241.create!(objid: 'w241-unique-001', name: 'alpha')
Widget241.name_index.get('alpha')
#=> 'w241-unique-001'

## BUG #241: destroy! leaves a stale entry in the class-level unique_index
# Expected behavior: after destroy!, the `name_index` no longer contains
# an entry for 'alpha' (so a subsequent create! with the same name
# succeeds instead of raising RecordExistsError).
@w1.destroy!
Widget241.name_index.get('alpha')
#=> nil

## BUG #241: re-creating with the same indexed value succeeds after destroy!
# With the stale entry removed, this should not raise RecordExistsError.
@w1b = Widget241.create!(objid: 'w241-unique-002', name: 'alpha')
Widget241.name_index.get('alpha')
#=> 'w241-unique-002'

## Class-level multi_index is populated by save
@m1 = Widget241.create!(objid: 'w241-multi-001', name: 'm-one',   category: 'tools')
@m2 = Widget241.create!(objid: 'w241-multi-002', name: 'm-two',   category: 'tools')
@m3 = Widget241.create!(objid: 'w241-multi-003', name: 'm-three', category: 'tools')
Widget241.category_index_for('tools').members.sort
#=> ['w241-multi-001', 'w241-multi-002', 'w241-multi-003']

## BUG #241: destroy! leaves stale entries in the class-level multi_index
# Expected behavior: after destroying m2, only m1 and m3 remain in the
# per-value set for 'tools' -- m2's identifier should be gone.
@m2.destroy!
Widget241.category_index_for('tools').members.sort
#=> ['w241-multi-001', 'w241-multi-003']

## BUG #241: re-creating with the same multi_index value succeeds after destroy!
# This verifies the per-value set is usable for new members after cleanup.
@m2b = Widget241.create!(objid: 'w241-multi-004', name: 'm-two-again', category: 'tools')
Widget241.category_index_for('tools').members.include?('w241-multi-004')
#=> true

## Regression: destroy! still removes the object hash
# This is the unchanged existing behavior -- confirms we didn't break
# the basic destroy! path while exercising the index cleanup bug.
@r1 = Widget241.create!(objid: 'w241-regress-001', name: 'reg-one', category: 'regress')
@r1.destroy!
Widget241.exists?('w241-regress-001')
#=> false

## Regression: destroy! still removes from the instances timeline
# Another existing guarantee: `remove_from_instances!` runs inside destroy!.
Widget241.in_instances?('w241-regress-001')
#=> false

## Regression: destroy! on a never-persisted object does not raise
# The generated remove_from_class_#{index_name} methods short-circuit via
# `return unless field_value`, so destroying an instance that was never
# saved (all indexed fields still nil) must be a safe no-op.
begin
  Widget241.new(objid: 'w241-unsaved-001').destroy!
  :no_raise
rescue StandardError => e
  "raised: #{e.class.name}"
end
#=> :no_raise

## Instance-scoped index cleanup is out of scope for #241 (documented limitation)
# The fix in #241 covers only class-level indexes. Instance-scoped indexes
# (`within: SomeClass`) require a parent context to resolve the set, so
# destroy! -- which has no parent reference -- cannot clean them up here.
# This test asserts the *current, unchanged* behavior so we notice if it
# ever changes unintentionally. Do not "fix" this by making the assertion
# match the class-level cleanup behavior; tracking is separate from #241.
class ::Widget241ScopedCompany < Familia::Horreum
  feature :relationships
  identifier_field :company_id
  field :company_id
end

class ::Widget241ScopedEmployee < Familia::Horreum
  feature :relationships
  identifier_field :emp_id
  field :emp_id
  field :badge

  # Instance-scoped unique index -- parent context is Widget241ScopedCompany.
  unique_index :badge, :badge_index, within: Widget241ScopedCompany
end

@scope_company = Widget241ScopedCompany.create!(company_id: 'w241co-001')
@scope_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-001', badge: 'B-42')
# Instance-scoped indexes don't auto-populate -- they need the parent context.
@scope_emp.add_to_widget241scoped_company_badge_index(@scope_company)
@scope_company.badge_index.has_key?('B-42')
#=> true

## Documented limitation: instance-scoped entry persists after destroy!
# This is the known gap outside #241's scope. Flipping this expectation
# would require threading parent context through destroy! -- tracked
# separately.
@scope_emp.destroy!
@scope_company.badge_index.has_key?('B-42')
#=> true

# Teardown: flush the database and remove throwaway constants so this
# tryout doesn't pollute sibling suites (index keys in particular can
# otherwise interfere with re-run iterations).
Familia.dbclient.flushdb
Object.send(:remove_const, :Widget241) if Object.const_defined?(:Widget241)
Object.send(:remove_const, :Widget241ScopedEmployee) if Object.const_defined?(:Widget241ScopedEmployee)
Object.send(:remove_const, :Widget241ScopedCompany) if Object.const_defined?(:Widget241ScopedCompany)
