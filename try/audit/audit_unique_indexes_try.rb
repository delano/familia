# try/audit/audit_unique_indexes_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class AuditIndexedUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :role
  field :name

  unique_index :email, :email_lookup
end

# Clean up
begin
  existing = Familia.dbclient.keys('audit_indexed_user:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditIndexedUser.instances.clear
AuditIndexedUser.email_lookup.clear

## audit_unique_indexes exists as class method
AuditIndexedUser.respond_to?(:audit_unique_indexes)
#=> true

## audit_unique_indexes returns array
AuditIndexedUser.audit_unique_indexes.is_a?(Array)
#=> true

## Clean state: no stale entries
@u1 = AuditIndexedUser.new(user_id: 'au-1', email: 'alice@test.com', name: 'Alice')
@u1.save
@u2 = AuditIndexedUser.new(user_id: 'au-2', email: 'bob@test.com', name: 'Bob')
@u2.save
@result = AuditIndexedUser.audit_unique_indexes
@result.first[:stale]
#=> []

## Clean state: no missing entries
@result.first[:missing]
#=> []

## Clean state: index_name is correct
@result.first[:index_name]
#=> :email_lookup

## Stale entry: manually inject wrong value via raw Redis
AuditIndexedUser.dbclient.hset(AuditIndexedUser.email_lookup.dbkey, 'old@test.com', '"au-999"')
@result = AuditIndexedUser.audit_unique_indexes
@result.first[:stale].any? { |s| s[:field_value] == 'old@test.com' }
#=> true

## Stale entry reason is object_missing
@result.first[:stale].find { |s| s[:field_value] == 'old@test.com' }[:reason]
#=> :object_missing

## Missing entry: clear index but keep objects
AuditIndexedUser.email_lookup.clear
@result = AuditIndexedUser.audit_unique_indexes
@result.first[:missing].size
#=> 2

## Missing entries contain the right identifiers
@result.first[:missing].map { |m| m[:identifier] }.sort
#=> ['au-1', 'au-2']

## Value mismatch detection: inject wrong identifier for alice's email
AuditIndexedUser.email_lookup.clear
@u1.save  # re-indexes
@u2.save
AuditIndexedUser.dbclient.hset(AuditIndexedUser.email_lookup.dbkey, 'alice@test.com', '"au-2"')
@result = AuditIndexedUser.audit_unique_indexes
@stale = @result.first[:stale].find { |s| s[:field_value] == 'alice@test.com' }
@stale[:reason]
#=> :value_mismatch

# Teardown
begin
  existing = Familia.dbclient.keys('audit_indexed_user:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
AuditIndexedUser.instances.clear
AuditIndexedUser.email_lookup.clear
