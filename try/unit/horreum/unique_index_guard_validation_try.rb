# try/unit/horreum/unique_index_guard_validation_try.rb

#
# Unique index guard validation tests
# Tests the guard_unique_*! methods for both class-level and instance-scoped indexes
#

require_relative '../../support/helpers/test_helpers'

# Test classes for unique index guard validation
class ::GuardUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :username

  # Class-level unique indexes (auto-validated on save)
  unique_index :email, :email_index
  unique_index :username, :username_index
end

class ::GuardCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name
end

class ::GuardEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :badge_number
  field :email

  # Instance-scoped unique index (manually validated)
  unique_index :badge_number, :badge_index, within: GuardCompany

  # Class-level unique index (auto-validated)
  unique_index :email, :email_index
end

# Setup
@user_id1 = "user_#{rand(1000000)}"
@user_id2 = "user_#{rand(1000000)}"
@company_id = "comp_#{rand(1000000)}"
@emp_id1 = "emp_#{rand(1000000)}"
@emp_id2 = "emp_#{rand(1000000)}"

@company = GuardCompany.new(company_id: @company_id, name: 'Test Corp')
@company.save

# =============================================
# 1. Class-Level Unique Index Guard Methods
# =============================================

## Guard method exists for class-level unique index
@user1 = GuardUser.new(user_id: @user_id1, email: 'test@example.com', username: 'testuser')
@user1.respond_to?(:guard_unique_email_index!)
#=> true

## Guard passes when no conflict exists
@user1.guard_unique_email_index!
#=> nil

## Save succeeds after guard passes
@user1.save
#=> true

## Guard fails when duplicate email exists
@user2 = GuardUser.new(user_id: @user_id2, email: 'test@example.com', username: 'different')
begin
  @user2.guard_unique_email_index!
  false
rescue Familia::RecordExistsError => e
  e.message.include?('GuardUser exists email=test@example.com')
end
#=> true

## Save automatically calls guard and raises error
begin
  @user2.save
  false
rescue Familia::RecordExistsError
  true
end
#=> true

## Guard allows same identifier (updating existing record)
@user1_copy = GuardUser.new(user_id: @user_id1, email: 'test@example.com', username: 'testuser')
@user1_copy.guard_unique_email_index!
#=> nil

## Guard handles nil field values gracefully
@user_nil = GuardUser.new(user_id: "user_nil_#{rand(1000000)}", email: nil, username: 'niluser')
@user_nil.guard_unique_email_index!
#=> nil

## Guard handles empty string field values
@user_empty1 = GuardUser.new(user_id: "user_empty1_#{rand(1000000)}", email: '', username: 'empty1')
@user_empty1.save
@user_empty2 = GuardUser.new(user_id: "user_empty2_#{rand(1000000)}", email: '', username: 'empty2')
begin
  @user_empty2.save
  false
rescue Familia::RecordExistsError => e
  e.message.include?('GuardUser exists email=')
end
#=> true

# =============================================
# 2. Instance-Scoped Unique Index Guard Methods
# =============================================

## Guard method exists for instance-scoped unique index
@emp1 = GuardEmployee.new(emp_id: @emp_id1, badge_number: 'BADGE123', email: 'emp1@example.com')
@emp1.respond_to?(:guard_unique_guard_company_badge_index!)
#=> true

## Guard method requires parent instance parameter
@emp1.method(:guard_unique_guard_company_badge_index!).arity
#=> 1

## Guard passes when no conflict exists in parent's index
@emp1.guard_unique_guard_company_badge_index!(@company)
#=> nil

## Can add to index after guard passes
@emp1.add_to_guard_company_badge_index(@company)
@company.badge_index.has_key?('BADGE123')
#=> true

## Guard fails when duplicate badge exists in same company
@emp2 = GuardEmployee.new(emp_id: @emp_id2, badge_number: 'BADGE123', email: 'emp2@example.com')
begin
  @emp2.guard_unique_guard_company_badge_index!(@company)
  false
rescue Familia::RecordExistsError => e
  e.message.include?('GuardEmployee exists in GuardCompany with badge_number=BADGE123')
end
#=> true

## Guard allows same employee to re-add (idempotent)
@emp1.guard_unique_guard_company_badge_index!(@company)
#=> nil

## Guard passes for different company (different scope)
@company2_id = "comp_#{rand(1000000)}"
@company2 = GuardCompany.new(company_id: @company2_id, name: 'Other Corp')
@company2.save
@emp2.guard_unique_guard_company_badge_index!(@company2)
#=> nil

## Can add same badge to different company
@emp2.add_to_guard_company_badge_index(@company2)
@company2.badge_index.has_key?('BADGE123')
#=> true

## Guard handles nil parent instance gracefully
@emp3 = GuardEmployee.new(emp_id: "emp_#{rand(1000000)}", badge_number: 'BADGE456', email: 'emp3@example.com')
@emp3.guard_unique_guard_company_badge_index!(nil)
#=> nil

## Guard handles nil badge_number gracefully
@emp_nil = GuardEmployee.new(emp_id: "emp_nil_#{rand(1000000)}", badge_number: nil, email: 'empnil@example.com')
@emp_nil.guard_unique_guard_company_badge_index!(@company)
#=> nil

# =============================================
# 3. Mixed Class and Instance-Scoped Validation
# =============================================

## Employee has both class-level and instance-scoped indexes
@emp4_id = "emp_#{rand(1000000)}"
@emp4 = GuardEmployee.new(emp_id: @emp4_id, badge_number: 'BADGE789', email: 'unique@example.com')
@emp4.class
#=> GuardEmployee

## Class-level email index auto-validates on save
@emp4.save
GuardEmployee.find_by_email('unique@example.com')&.emp_id
#=> @emp4_id

## Instance-scoped badge index must be manually validated and added
@emp4.guard_unique_guard_company_badge_index!(@company)
@emp4.add_to_guard_company_badge_index(@company)
@company.badge_index.has_key?('BADGE789')
#=> true

## Duplicate class-level index caught by save
@emp5_id = "emp_#{rand(1000000)}"
@emp5 = GuardEmployee.new(emp_id: @emp5_id, badge_number: 'BADGE999', email: 'unique@example.com')
begin
  @emp5.save
  false
rescue Familia::RecordExistsError => e
  e.message.include?('GuardEmployee exists email=unique@example.com')
end
#=> true

## Duplicate instance-scoped index requires manual guard
@emp6_id = "emp_#{rand(1000000)}"
@emp6 = GuardEmployee.new(emp_id: @emp6_id, badge_number: 'BADGE789', email: 'emp6@example.com')
@emp6.save  # Succeeds - no auto-validation of instance-scoped indexes
begin
  @emp6.guard_unique_guard_company_badge_index!(@company)
  false
rescue Familia::RecordExistsError => e
  e.message.include?('GuardEmployee exists in GuardCompany with badge_number=BADGE789')
end
#=> true

# =============================================
# 4. Guard Method Error Messages
# =============================================

## Class-level guard error includes class and field
@user_dup = GuardUser.new(user_id: "user_dup_#{rand(1000000)}", email: 'test@example.com', username: 'dupuser')
begin
  @user_dup.guard_unique_email_index!
rescue Familia::RecordExistsError => e
  [e.message.include?('GuardUser'), e.message.include?('email=test@example.com')]
end
#=> [true, true]

## Instance-scoped guard error includes both classes and field
begin
  @emp2.guard_unique_guard_company_badge_index!(@company)
rescue Familia::RecordExistsError => e
  [e.message.include?('GuardEmployee'), e.message.include?('GuardCompany'), e.message.include?('badge_number=BADGE123')]
end
#=> [true, true, true]

## RecordExistsError is correct type
begin
  @emp2.guard_unique_guard_company_badge_index!(@company)
rescue => e
  e.class
end
#=> Familia::RecordExistsError

# =============================================
# 5. Transaction Context Behavior
# =============================================

## Guard works outside transaction
@user_tx = GuardUser.new(user_id: "user_tx_#{rand(1000000)}", email: 'tx@example.com', username: 'txuser')
@user_tx.guard_unique_email_index!
#=> nil

## Guard is skipped during transaction (can't read Redis::Future)
result = GuardUser.transaction do
  @user_in_tx = GuardUser.new(user_id: "user_in_tx_#{rand(1000000)}", email: 'intx@example.com', username: 'intxuser')
  # guard_unique_indexes! returns early when Fiber[:familia_transaction] is set
  @user_in_tx.send(:guard_unique_indexes!)
end
result.class
#=> MultiResult

# Teardown - clean up test objects
[@user1, @user2, @user_nil, @user_empty1, @user_empty2, @user_dup, @user_tx].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

[@emp1, @emp2, @emp3, @emp_nil, @emp4, @emp5, @emp6].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

[@company, @company2].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

# Clean up class-level indexes
[GuardUser.email_index, GuardUser.username_index, GuardEmployee.email_index].each do |index|
  index.delete! if index.respond_to?(:delete!) && index.respond_to?(:exists?) && index.exists?
end
