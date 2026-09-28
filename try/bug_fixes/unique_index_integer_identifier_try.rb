# try/bug_fixes/unique_index_integer_identifier_try.rb
#
# frozen_string_literal: true

# The unique-index guards read the owning identifier back from a reference
# hash, which returns the stored String ("42"), and compared it with the
# record's identifier. When the identifier field holds an Integer (JSON field
# deserialization keeps it one), "42" != 42 made the record look like a rival
# owner of its own entry: it saved once, then every later save raised
# Familia::RecordExistsError. The instance-scoped guard behind
# add_to_<scope>_<index> failed the same way on the second call. Both guards
# now compare the identifier's string form.

require_relative '../support/helpers/test_helpers'

class ::IntIdUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :email
  unique_index :email, :email_lookup
end

class ::IntIdCompany < Familia::Horreum
  feature :relationships
  identifier_field :company_id
  field :company_id
end

class ::IntIdEmployee < Familia::Horreum
  feature :relationships
  identifier_field :emp_id
  field :emp_id
  field :badge
  unique_index :badge, :badge_index, within: ::IntIdCompany
end

IntIdUser.email_lookup.delete!
@user = IntIdUser.new(uid: 42, email: 'int-id@example.com')

## a record with an Integer identifier saves the first time
@user.save
#=> true

## the identifier is still an Integer in memory
@user.uid.class
#=> Integer

## the same record saves again instead of being refused its own index entry
@user.save
#=> true

## a freshly loaded copy keeps the Integer identifier and saves too
@loaded = IntIdUser.load(42)
[@loaded.uid.class, @loaded.save]
#=> [Integer, true]

## the index still points at the record
IntIdUser.email_lookup.get('int-id@example.com')
#=> '42'

## a different record with the same email is still refused
IntIdUser.new(uid: 43, email: 'int-id@example.com').save
#=!> Familia::RecordExistsError

## the refused record did not take over the index entry
IntIdUser.email_lookup.get('int-id@example.com')
#=> '42'

## the instance-scoped guard accepts a second add of the same Integer-identified record
@company = IntIdCompany.new(company_id: 'int_id_co_1')
@company.save
@employee = IntIdEmployee.new(emp_id: 7, badge: 'b-100')
@employee.save
@employee.add_to_int_id_company_badge_index(@company)
@employee.add_to_int_id_company_badge_index(@company)
@company.badge_index.get('b-100')
#=> '7'

## a different employee with the same badge in the same company is still refused
@rival = IntIdEmployee.new(emp_id: 8, badge: 'b-100')
@rival.save
@rival.add_to_int_id_company_badge_index(@company)
#=!> Familia::RecordExistsError

## the scoped index still points at the first employee
@company.badge_index.get('b-100')
#=> '7'

@company.badge_index.delete!
@rival.destroy!
@employee.destroy!
@company.destroy!
IntIdUser.email_lookup.delete!
@user.destroy!
