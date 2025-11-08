# try/unit/horreum/automatic_index_validation_try.rb
#
# frozen_string_literal: true

#
# Automatic index validation tests
# Tests that unique index validation happens automatically when adding to indexes
#

require_relative '../../support/helpers/test_helpers'

# Test classes for automatic validation
class ::AutoValidCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name
end

class ::AutoValidEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :badge_number
  field :email

  # Instance-scoped unique index (should auto-validate in add_to_* methods)
  unique_index :badge_number, :badge_index, within: AutoValidCompany

  # Class-level unique index (auto-validates in save)
  unique_index :email, :email_index
end

class ::AutoValidUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email

  unique_index :email, :email_index
end

# Setup
@company_id = "comp_#{rand(1000000)}"
@company = AutoValidCompany.new(company_id: @company_id, name: 'Test Corp')
@company.save

@emp1_id = "emp_#{rand(1000000)}"
@emp2_id = "emp_#{rand(1000000)}"

# =============================================
# 1. Automatic Validation in add_to_* Methods
# =============================================

## First employee can add badge to company index
@emp1 = AutoValidEmployee.new(emp_id: @emp1_id, badge_number: 'BADGE123', email: 'emp1@example.com')
@emp1.save  # Save first to establish class-level email index
@emp1.add_to_auto_valid_company_badge_index(@company)
@company.badge_index.has_key?('BADGE123')
#=> true

## Duplicate badge is automatically rejected without manual guard call
@emp2 = AutoValidEmployee.new(emp_id: @emp2_id, badge_number: 'BADGE123', email: 'emp2@example.com')
begin
  @emp2.add_to_auto_valid_company_badge_index(@company)
  false
rescue Familia::RecordExistsError => e
  e.message.include?('AutoValidEmployee exists in AutoValidCompany with badge_number=BADGE123')
end
#=> true

## Badge was not added after validation failure
@company.badge_index.get('BADGE123')
#=> @emp1_id

## Different badge number works fine
@emp2.badge_number = 'BADGE456'
@emp2.add_to_auto_valid_company_badge_index(@company)
@company.badge_index.has_key?('BADGE456')
#=> true

## Same employee can re-add (idempotent)
@emp1.add_to_auto_valid_company_badge_index(@company)
@company.badge_index.get('BADGE123')
#=> @emp1_id

## Different company allows same badge (scoped uniqueness)
@company2_id = "comp_#{rand(1000000)}"
@company2 = AutoValidCompany.new(company_id: @company2_id, name: 'Other Corp')
@company2.save
@emp3_id = "emp_#{rand(1000000)}"
@emp3 = AutoValidEmployee.new(emp_id: @emp3_id, badge_number: 'BADGE123', email: 'emp3@example.com')
@emp3.add_to_auto_valid_company_badge_index(@company2)
@company2.badge_index.has_key?('BADGE123')
#=> true

## Nil badge_number handled gracefully (no validation or addition)
@emp_nil = AutoValidEmployee.new(emp_id: "emp_nil_#{rand(1000000)}", badge_number: nil, email: 'empnil@example.com')
@emp_nil.add_to_auto_valid_company_badge_index(@company)
#=> nil

## Nil parent handled gracefully (no validation or addition)
@emp4 = AutoValidEmployee.new(emp_id: "emp4_#{rand(1000000)}", badge_number: 'BADGE789', email: 'emp4@example.com')
@emp4.add_to_auto_valid_company_badge_index(nil)
#=> nil

# =============================================
# 2. Transaction Detection in save()
# =============================================

## Normal save works outside transaction
@user1_id = "user_#{rand(1000000)}"
@user1 = AutoValidUser.new(user_id: @user1_id, email: 'user1@example.com')
@user1.save
#=> true

## save() raises error when called within transaction
@user2_id = "user_#{rand(1000000)}"
begin
  AutoValidUser.transaction do
    @user2 = AutoValidUser.new(user_id: @user2_id, email: 'user2@example.com')
    @user2.save
  end
  false
rescue Familia::OperationModeError => e
  e.message.include?('Cannot call save within a transaction')
end
#=> true

## Object was not saved due to transaction error
AutoValidUser.find_by_email('user2@example.com')
#=> nil

## Transaction with explicit field updates works (bypass save)
@user3_id = "user_#{rand(1000000)}"
@user3 = AutoValidUser.new(user_id: @user3_id, email: 'user3@example.com')
AutoValidUser.transaction do |_tx|
  @user3.hmset(@user3.to_h_for_storage)
end
@user3.exists?
#=> true

## save() works after transaction completes
@user4_id = "user_#{rand(1000000)}"
AutoValidUser.transaction do
  # Do something else in transaction
end
@user4 = AutoValidUser.new(user_id: @user4_id, email: 'user4@example.com')
@user4.save
#=> true

# =============================================
# 3. Combined Automatic Validation Scenarios
# =============================================

## Employee with duplicate class-level email caught in save
@emp5_id = "emp_#{rand(1000000)}"
@emp5 = AutoValidEmployee.new(emp_id: @emp5_id, badge_number: 'BADGE999', email: 'emp1@example.com')
begin
  @emp5.save
  false
rescue Familia::RecordExistsError => e
  e.message.include?('AutoValidEmployee exists email=emp1@example.com')
end
#=> true

## Employee can save with unique email
@emp1.save
AutoValidEmployee.find_by_email('emp1@example.com')&.emp_id
#=> @emp1_id

## After save, duplicate instance-scoped index still caught automatically
@emp6_id = "emp_#{rand(1000000)}"
@emp6 = AutoValidEmployee.new(emp_id: @emp6_id, badge_number: 'BADGE123', email: 'emp6@example.com')
@emp6.save  # Class-level index is fine
begin
  @emp6.add_to_auto_valid_company_badge_index(@company)  # Instance-scoped duplicate
  false
rescue Familia::RecordExistsError => e
  e.message.include?('badge_number=BADGE123')
end
#=> true

# =============================================
# 4. Error Message Quality
# =============================================

## Instance-scoped validation error includes both class names
begin
  @emp2.badge_number = 'BADGE123'  # Reset to duplicate
  @emp2.add_to_auto_valid_company_badge_index(@company)
rescue Familia::RecordExistsError => e
  [e.message.include?('AutoValidEmployee'), e.message.include?('AutoValidCompany')]
end
#=> [true, true]

## Instance-scoped validation error includes field name and value
begin
  @emp2.add_to_auto_valid_company_badge_index(@company)
rescue Familia::RecordExistsError => e
  [e.message.include?('badge_number'), e.message.include?('BADGE123')]
end
#=> [true, true]

## Error type is RecordExistsError
begin
  @emp2.add_to_auto_valid_company_badge_index(@company)
rescue => e
  e.class
end
#=> Familia::RecordExistsError

# =============================================
# 5. Performance - No Double Validation
# =============================================

## Manual guard call before add_to_* is redundant but harmless
@emp7_id = "emp_#{rand(1000000)}"
@emp7 = AutoValidEmployee.new(emp_id: @emp7_id, badge_number: 'BADGE777', email: 'emp7@example.com')
@emp7.guard_unique_auto_valid_company_badge_index!(@company)
@emp7.add_to_auto_valid_company_badge_index(@company)
@company.badge_index.has_key?('BADGE777')
#=> true

## Manual guard call detects duplicate
@emp8_id = "emp_#{rand(1000000)}"
@emp8 = AutoValidEmployee.new(emp_id: @emp8_id, badge_number: 'BADGE777', email: 'emp8@example.com')
begin
  @emp8.guard_unique_auto_valid_company_badge_index!(@company)  # Should fail - duplicate badge
  false
rescue Familia::RecordExistsError
  true
end
#=> true

# Teardown - clean up test objects
[@emp1, @emp2, @emp3, @emp_nil, @emp4, @emp5, @emp6, @emp7, @emp8].compact.each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

[@user1, @user3, @user4].compact.each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

[@company, @company2].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

# Clean up class-level indexes
[AutoValidEmployee.email_index, AutoValidUser.email_index].each do |index|
  index.delete! if index.respond_to?(:delete!) && index.respond_to?(:exists?) && index.exists?
end
