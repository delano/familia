# try/horreum/auto_indexing_on_save_try.rb

#
# Auto-indexing on save functionality tests
# Tests automatic index population when Familia::Horreum objects are saved
#

require_relative '../helpers/test_helpers'

# Test classes for auto-indexing functionality
class ::AutoIndexUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :username
  field :department

  # Class-level unique indexes (should auto-populate on save)
  unique_index :email, :email_index
  unique_index :username, :username_index
end

class ::AutoIndexCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name
end

class ::AutoIndexEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :badge_number
  field :department

  # Instance-scoped indexes (should NOT auto-populate - require parent context)
  unique_index :badge_number, :badge_index, within: AutoIndexCompany
  multi_index :department, :dept_index, within: AutoIndexCompany
end

# Setup
@user_id = "user_#{rand(1000000)}"
@user = AutoIndexUser.new(user_id: @user_id, email: 'test@example.com', username: 'testuser', department: 'engineering')

@company_id = "comp_#{rand(1000000)}"
@company = AutoIndexCompany.new(company_id: @company_id, name: 'Test Corp')

@emp_id = "emp_#{rand(1000000)}"
@employee = AutoIndexEmployee.new(emp_id: @emp_id, badge_number: 'BADGE123', department: 'sales')

# =============================================
# 1. Class-Level Unique Index Auto-Population
# =============================================

## Unique index is empty before save
AutoIndexUser.email_index.has_key?('test@example.com')
#=> false

## Save automatically populates unique index
@user.save
AutoIndexUser.email_index.has_key?('test@example.com')
#=> true

## Auto-populated index maps to correct identifier
AutoIndexUser.email_index.get('test@example.com')
#=> @user_id

## Finder method works after auto-indexing
found = AutoIndexUser.find_by_email('test@example.com')
found&.user_id
#=> @user_id

## Multiple unique indexes auto-populate on same save
AutoIndexUser.username_index.get('testuser')
#=> @user_id

## Subsequent saves maintain index (idempotent)
@user.save
AutoIndexUser.email_index.get('test@example.com')
#=> @user_id

## Changing indexed field and saving adds new entry (old entry remains unless manually removed)
# Note: Auto-indexing is idempotent addition only - updates require manual update_in_class_* calls
@user.email = 'newemail@example.com'
@user.save
# New email is indexed, but old email remains (expected behavior - use update_in_class_* for proper updates)
[AutoIndexUser.email_index.has_key?('test@example.com'), AutoIndexUser.email_index.get('newemail@example.com') == @user_id]
#=> [true, true]

# =============================================
# 2. Instance-Scoped Indexes (Manual Only)
# =============================================

## Instance-scoped indexes do NOT auto-populate on save
@employee.save
@company.badge_index.has_key?('BADGE123')
#=> false

## Instance-scoped indexes remain manual (require parent context)
@employee.add_to_auto_index_company_badge_index(@company)
@company.badge_index.has_key?('BADGE123')
#=> true

# =============================================
# 3. Edge Cases and Error Handling
# =============================================

## Nil field values handled gracefully
@user_nil_id = "user_nil_#{rand(1000000)}"
@user_nil = AutoIndexUser.new(user_id: @user_nil_id, email: nil, username: nil, department: nil)
@user_nil.save
AutoIndexUser.email_index.has_key?('')
#=> false

## Empty string field values handled gracefully
@user_empty_id = "user_empty_#{rand(1000000)}"
@user_empty = AutoIndexUser.new(user_id: @user_empty_id, email: '', username: '', department: '')
@user_empty.save
# Empty strings are indexed (they're valid string values, just empty)
AutoIndexUser.email_index.has_key?('')
#=> true

## Auto-indexing works with create method
@user2_id = "user_#{rand(1000000)}"
@user2 = AutoIndexUser.create(user_id: @user2_id, email: 'create@example.com', username: 'createuser', department: 'marketing')
AutoIndexUser.find_by_email('create@example.com')&.user_id
#=> @user2_id

## Auto-indexing idempotent with multiple saves
@user2.save
@user2.save
@user2.save
AutoIndexUser.email_index.get('create@example.com')
#=> @user2_id

## Field update followed by save adds new entry (use update_in_class_* for proper updates)
old_email = @user2.email
@user2.email = 'updated@example.com'
@user2.save
# Both old and new emails are indexed (auto-indexing doesn't remove old values)
# For proper updates that remove old values, use: @user2.update_in_class_email_index(old_email)
[AutoIndexUser.email_index.has_key?(old_email), AutoIndexUser.email_index.get('updated@example.com') == @user2_id]
#=> [true, true]

# =============================================
# 4. Integration with Other Features
# =============================================

## Auto-indexing works with transient fields
class ::AutoIndexWithTransient < Familia::Horreum
  feature :transient_fields
  feature :relationships

  identifier_field :id
  field :id
  field :email
  transient_field :temp_value

  unique_index :email, :email_index
end

@transient_id = "trans_#{rand(1000000)}"
@transient_obj = AutoIndexWithTransient.new(id: @transient_id, email: 'transient@example.com', temp_value: 'ignored')
@transient_obj.save
AutoIndexWithTransient.find_by_email('transient@example.com')&.id
#=> @transient_id

## Auto-indexing works regardless of other features
# Just verify that the feature system doesn't interfere
@transient_obj.class.respond_to?(:indexing_relationships)
#=> true

# =============================================
# 5. Performance and Behavior Verification
# =============================================

## Auto-indexing has negligible overhead (no existence checks)
# This test verifies the design: we use idempotent commands (HSET, SADD)
# rather than checking if the index exists before updating
@user4_id = "user_#{rand(1000000)}"
@user4 = AutoIndexUser.new(user_id: @user4_id, email: 'perf@example.com', username: 'perfuser', department: 'ops')

# Save multiple times - all should succeed with same result
@user4.save
@user4.save
@user4.save

AutoIndexUser.email_index.get('perf@example.com')
#=> @user4_id

## Auto-indexing only processes class-level indexes
# Verify no errors when instance-scoped indexes present
@employee2_id = "emp_#{rand(1000000)}"
@employee2 = AutoIndexEmployee.new(emp_id: @employee2_id, badge_number: 'BADGE456', department: 'engineering')
@employee2.save  # Should not error, just skip instance-scoped indexes
@employee2.emp_id
#=> @employee2_id

# Teardown - clean up test objects
[@user, @user2, @user4, @user_nil, @user_empty, @company, @employee, @employee2, @transient_obj].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

# Clean up class-level indexes
[AutoIndexUser.email_index, AutoIndexUser.username_index].each do |index|
  index.delete! if index.respond_to?(:delete!) && index.respond_to?(:exists?) && index.exists?
end
