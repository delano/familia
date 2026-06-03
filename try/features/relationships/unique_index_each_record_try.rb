# try/features/relationships/unique_index_each_record_try.rb
#
# frozen_string_literal: true

# Tests for issue #276: unique_index hashkeys were created without the
# `class:` option, so `each_record` raised Familia::Problem ("requires a
# reference DataType with a :class option that responds to load_multi").
#
# The fix declares unique_index hashkeys as proper reference types
# (`class: indexed_class, reference: true`), matching the `instances`
# collection pattern, and teaches `each_record` to extract the stored
# identifier (the hash value) rather than the indexed field (the hash key).

require_relative '../../support/helpers/test_helpers'

class UIERUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email

  unique_index :email, :email_lookup
end

class UIERCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
end

class UIEREmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :badge_number

  unique_index :badge_number, :badge_index, within: UIERCompany
end

# Setup
UIERUser.email_lookup.clear
UIERUser.instances.clear
@u0 = UIERUser.new(user_id: 'u0', email: 'u0@example.com')
@u0.save
@u1 = UIERUser.new(user_id: 'u1', email: 'u1@example.com')
@u1.save
@u2 = UIERUser.new(user_id: 'u2', email: 'u2@example.com')
@u2.save

# ============================================================
# The index hashkey is a proper reference type
# ============================================================

## Class-level unique_index hashkey carries the indexed class
UIERUser.email_lookup.opts[:class]
#=> UIERUser

## Class-level unique_index hashkey is a reference type
UIERUser.email_lookup.opts[:reference]
#=> true

## Stored values are raw identifiers (not JSON-encoded)
UIERUser.dbclient.hget(UIERUser.email_lookup.dbkey, 'u1@example.com')
#=> "u1"

## find_by_<field> still resolves the record
UIERUser.find_by_email('u1@example.com')&.user_id
#=> "u1"

# ============================================================
# each_record on a class-level unique_index (issue #276)
# ============================================================

## each_record no longer raises and yields Horreum records
records = []
UIERUser.email_lookup.each_record { |r| records << r }
records.all? { |r| r.is_a?(UIERUser) }
#=> true

## each_record yields every indexed record (by identifier, not field)
records = []
UIERUser.email_lookup.each_record { |r| records << r }
records.map(&:user_id).sort
#=> ["u0", "u1", "u2"]

## each_record returns an Enumerator when no block is given
UIERUser.email_lookup.each_record.class
#=> Enumerator

## each_record Enumerator composes with Enumerable
UIERUser.email_lookup.each_record.map(&:email).sort
#=> ["u0@example.com", "u1@example.com", "u2@example.com"]

## each_record honors batch_size
records = []
UIERUser.email_lookup.each_record(batch_size: 1) { |r| records << r }
records.map(&:user_id).sort
#=> ["u0", "u1", "u2"]

## each_record skips ghost entries (value points at a deleted record)
UIERUser.dbclient.hset(UIERUser.email_lookup.dbkey, 'ghost@example.com', 'u-ghost')
records = []
UIERUser.email_lookup.each_record { |r| records << r }
result = records.map(&:user_id).sort
UIERUser.email_lookup.remove('ghost@example.com')
result
#=> ["u0", "u1", "u2"]

# ============================================================
# each_record on an instance-scoped unique_index
# ============================================================

## Instance-scoped unique_index hashkey is also a reference type
@company = UIERCompany.new(company_id: 'c1')
@company.badge_index.opts[:class]
#=> UIEREmployee

## Instance-scoped unique_index hashkey carries reference: true
@company.badge_index.opts[:reference]
#=> true

## each_record on the instance-scoped index yields the indexed employees
@company.badge_index.clear
@e1 = UIEREmployee.new(emp_id: 'e1', badge_number: 'B1')
@e1.save
@e2 = UIEREmployee.new(emp_id: 'e2', badge_number: 'B2')
@e2.save
@e1.add_to_uier_company_badge_index(@company)
@e2.add_to_uier_company_badge_index(@company)
records = []
@company.badge_index.each_record { |r| records << r }
records.map(&:emp_id).sort
#=> ["e1", "e2"]

# Teardown
UIERUser.email_lookup.clear
UIERUser.instances.clear
[@u0, @u1, @u2].each { |u| u.destroy! rescue nil }
@company.badge_index.clear rescue nil
[@e1, @e2].each { |e| e.destroy! rescue nil }
