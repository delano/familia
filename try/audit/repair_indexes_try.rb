# try/audit/repair_indexes_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class RepairIdxUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email

  unique_index :email, :email_lookup
end

# Clean up
begin
  existing = Familia.dbclient.keys('repair_idx_user:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairIdxUser.instances.clear
RepairIdxUser.email_lookup.clear

## repair_indexes! exists as class method
RepairIdxUser.respond_to?(:repair_indexes!)
#=> true

## Create objects and verify clean state
@u1 = RepairIdxUser.new(user_id: 'ri-1', email: 'ri1@test.com')
@u1.save
@u2 = RepairIdxUser.new(user_id: 'ri-2', email: 'ri2@test.com')
@u2.save
RepairIdxUser.audit_unique_indexes.first[:stale].size
#=> 0

## Corrupt index by adding stale entry via raw Redis
RepairIdxUser.dbclient.hset(RepairIdxUser.email_lookup.dbkey, 'gone@test.com', '"ri-999"')
RepairIdxUser.audit_unique_indexes.first[:stale].size
#=> 1

## repair_indexes! triggers rebuild and returns rebuilt index names
@result = RepairIdxUser.repair_indexes!
@result[:rebuilt]
#=> [:email_lookup]

## After repair, stale entry is gone
RepairIdxUser.audit_unique_indexes.first[:stale].size
#=> 0

## After repair, valid entries still work
RepairIdxUser.find_by_email('ri1@test.com')&.user_id
#=> "ri-1"

## repair_indexes! with clean state returns empty rebuilt list
@result = RepairIdxUser.repair_indexes!
@result[:rebuilt]
#=> []

## repair_indexes! accepts pre-computed audit results
RepairIdxUser.email_lookup.clear
@audit = RepairIdxUser.audit_unique_indexes
@result = RepairIdxUser.repair_indexes!(@audit)
@result[:rebuilt]
#=> [:email_lookup]

# Teardown
begin
  existing = Familia.dbclient.keys('repair_idx_user:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RepairIdxUser.instances.clear
RepairIdxUser.email_lookup.clear
