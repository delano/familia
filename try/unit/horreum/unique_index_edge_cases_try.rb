# try/unit/horreum/unique_index_edge_cases_try.rb
#
# frozen_string_literal: true

# Testing edge cases for unique index validation
# lib/familia/features/relationships/indexing/unique_index_generators.rb
# lib/familia/horreum/persistence.rb

require_relative '../../../lib/familia'

Familia.debug = false

# ========================================
# Setup: Define test models
# ========================================

class EdgeCaseCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :company_name

  # init receives no arguments - fields already set from new()
  # Use ||= to apply defaults if needed
  def init
    # No defaults needed for this class
    # Could add: @company_name ||= 'Unknown Company'
  end
end

class EdgeCaseEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :email
  field :badge_number
  field :department
  field :status

  # Class-level unique index for email (auto-populates on save)
  unique_index :email, :email_index

  # Instance-scoped unique index for badge_number within Company
  unique_index :badge_number, :badge_index, within: EdgeCaseCompany

  # Multi-index for department (1:many) within Company
  multi_index :department, :dept_index, within: EdgeCaseCompany

  # init receives no arguments - fields already set from new()
  # Use ||= to apply defaults if needed
  def init
    @status ||= 'active'  # Apply default status if not provided
  end
end

class EdgeCaseProduct < Familia::Horreum
  feature :relationships

  identifier_field :product_id
  field :product_id
  field :sku

  # Allow empty strings in unique index
  unique_index :sku, :sku_index

  # init receives no arguments - fields already set from new()
  # Use ||= to apply defaults if needed
  def init
    # No defaults needed for this class
  end
end

# Clear all indexes before starting
EdgeCaseEmployee.email_index.clear
EdgeCaseProduct.sku_index.clear

# ========================================
# Test 1: Duplicate instance-scoped index values
# ========================================

## Setup companies and employees
@company1 = EdgeCaseCompany.new(company_id: 'c1', company_name: 'Acme Corp')
@company2 = EdgeCaseCompany.new(company_id: 'c2', company_name: 'Tech Inc')
@company1.save
@company2.save
#=> true

## Create employee with badge_number in company1
@emp1 = EdgeCaseEmployee.new(emp_id: 'e1', email: 'john@test.com', badge_number: 'B12345')
@emp1.save  # This auto-populates email index
@emp1.add_to_edge_case_company_badge_index(@company1)  # Manual for instance-scoped
@company1.find_by_badge_number('B12345')&.emp_id
#=> 'e1'

## Create another employee with same badge_number - guard should detect duplicate
@emp2 = EdgeCaseEmployee.new(emp_id: 'e2', email: 'jane@test.com', badge_number: 'B12345')
@emp2.save  # Different email is OK
begin
  @emp2.guard_unique_edge_case_company_badge_index!(@company1)
  false
rescue Familia::RecordExistsError
  true
end
#=> true

## Same badge_number should work in different company (different scope)
@emp2.add_to_edge_case_company_badge_index(@company2)
@company2.find_by_badge_number('B12345')&.emp_id
#=> 'e2'

## Verify badge exists in both companies with different employees
[@company1.find_by_badge_number('B12345')&.emp_id, @company2.find_by_badge_number('B12345')&.emp_id]
#=> ['e1', 'e2']

## Cleanup for next test
EdgeCaseEmployee.email_index.clear
@company1.badge_index.clear
@company2.badge_index.clear
#=> 1

# ========================================
# Test 2: Field updates with auto-index cleanup
# ========================================

## Create employee with email (save auto-populates index)
@emp3 = EdgeCaseEmployee.new(emp_id: 'e3', email: 'original@test.com')
@emp3.save
EdgeCaseEmployee.find_by_email('original@test.com')&.emp_id
#=> 'e3'

## Update email - must manually update index (no automatic cleanup on field change)
old_email = @emp3.email
@emp3.email = 'updated@test.com'
@emp3.update_in_class_email_index(old_email)  # Manual update required
EdgeCaseEmployee.find_by_email('original@test.com')
#=> nil

## New email should resolve to employee
EdgeCaseEmployee.find_by_email('updated@test.com')&.emp_id
#=> 'e3'

## Update instance-scoped index
@emp3.badge_number = 'B99999'
@emp3.add_to_edge_case_company_badge_index(@company1)
@company1.find_by_badge_number('B99999')&.emp_id
#=> 'e3'

## Change badge and update index
old_badge = @emp3.badge_number
@emp3.badge_number = 'B11111'
@emp3.update_in_edge_case_company_badge_index(@company1, old_badge)
@company1.find_by_badge_number('B99999')
#=> nil

## New badge should work
@company1.find_by_badge_number('B11111')&.emp_id
#=> 'e3'

## Cleanup
EdgeCaseEmployee.email_index.clear
@company1.badge_index.clear
#=> 1

# ========================================
# Test 3: Save within explicit transactions (validation bypass)
# ========================================

## Create first employee successfully
@emp4 = EdgeCaseEmployee.new(emp_id: 'e4', email: 'txn@test.com')
@emp4.save
EdgeCaseEmployee.find_by_email('txn@test.com')&.emp_id
#=> 'e4'

## Save cannot be called inside transaction - it raises OperationModeError
@emp5 = EdgeCaseEmployee.new(emp_id: 'e5', email: 'txn@test.com')
error_raised = false
begin
  EdgeCaseEmployee.transaction do |tx|
    @emp5.save  # This will raise
  end
rescue Familia::OperationModeError => e
  error_raised = e.message.include?("Cannot call save within a transaction")
end
error_raised
#=> true

## However, we can bypass validation by manually adding to index inside transaction
result = EdgeCaseEmployee.transaction do |tx|
  # Manually add without validation (dangerous!)
  EdgeCaseEmployee.email_index['txn_bypass@test.com'] = 'e5'
  'manual_bypass'
end
result.successful?
#=> true

## After transaction, the manual entry exists (no validation occurred)
EdgeCaseEmployee.email_index['txn_bypass@test.com']
#=> 'e5'

## After transaction, the manual entry exists (no validation occurred)
EdgeCaseEmployee.email_index['txn_bypass@test.com']
#=> 'e5'

## Cleanup
EdgeCaseEmployee.email_index.clear
#=> 1

# ========================================
# Test 4: Multiple empty string values in same index
# ========================================

## Create product with empty SKU
@prod1 = EdgeCaseProduct.new(product_id: 'p1', sku: '')
@prod1.save
EdgeCaseProduct.find_by_sku('')&.product_id
#=> 'p1'

## Try to create another product with empty SKU - should fail
@prod2 = EdgeCaseProduct.new(product_id: 'p2', sku: '')
begin
  @prod2.save
  false
rescue Familia::RecordExistsError => e
  e.message.include?('sku=')
end
#=> true

## nil values should be skipped (not indexed)
@prod3 = EdgeCaseProduct.new(product_id: 'p3', sku: nil)
@prod3.save  # Should succeed - nil values aren't indexed
@prod3.identifier
#=> 'p3'

## Verify nil doesn't exist in index (empty string != nil)
EdgeCaseProduct.sku_index['']  # Empty string key
#=> 'p1'

## nil is not indexed
EdgeCaseProduct.sku_index.keys.include?(nil)
#=> false

## Cleanup
EdgeCaseProduct.sku_index.clear
#=> 1

# ========================================
# Test 5: Concurrent saves with same unique value
# ========================================

## Setup fresh index
EdgeCaseEmployee.email_index.clear
#=> 0

## Create two employees with same email (simulating race condition)
@emp6 = EdgeCaseEmployee.new(emp_id: 'e6', email: 'race@test.com')
@emp7 = EdgeCaseEmployee.new(emp_id: 'e7', email: 'race@test.com')
@emp7.emp_id
#=> 'e7'

## First save succeeds
@emp6.save
EdgeCaseEmployee.find_by_email('race@test.com')&.emp_id
#=> 'e6'

## Second save fails due to validation
begin
  @emp7.save
  false
rescue Familia::RecordExistsError
  true
end
#=> true

## Simulate race condition: both check validation, then both write
EdgeCaseEmployee.email_index.clear
@emp8 = EdgeCaseEmployee.new(emp_id: 'e8', email: 'race2@test.com')
@emp9 = EdgeCaseEmployee.new(emp_id: 'e9', email: 'race2@test.com')
[@emp8.emp_id, @emp9.emp_id]
#=> ['e8', 'e9']

## Both pass validation check (index is empty)
begin
  @emp8.guard_unique_email_index!
  @emp9.guard_unique_email_index!
  true
rescue
  false
end
#=> true

## Both write to index (last write wins in Redis)
@emp8.add_to_class_email_index
@emp9.add_to_class_email_index
# Verify the index contains the identifier (orphaned entry - wastes space but harmless)
EdgeCaseEmployee.email_index['race2@test.com']
#=> 'e9'

## find_by returns nil for orphaned index entries (object never saved)
# This is correct behavior - orphaned entries degrade gracefully to nil
EdgeCaseEmployee.find_by_email('race2@test.com')
#=> nil

## To properly handle concurrent saves, check existence inside transaction
# Note: Can't read inside MULTI block, so need WATCH/MULTI pattern
result = nil
EdgeCaseEmployee.dbclient.watch('edge_case_employee:email_index') do
  if EdgeCaseEmployee.email_index['race3@test.com'].nil?
    EdgeCaseEmployee.transaction do |tx|
      EdgeCaseEmployee.email_index['race3@test.com'] = 'e10'
      result = 'success'
    end
  else
    result = 'duplicate'
  end
end
result
#=> 'success'

## Cleanup
EdgeCaseEmployee.email_index.clear
#=> 1

# ========================================
# Edge Case: Update with validation in compound operation
# ========================================

## Test compound index updates in transaction
@company3 = EdgeCaseCompany.new(company_id: 'c3', company_name: 'Test Corp')
@company3.save
#=> true

## Create employee
@emp11 = EdgeCaseEmployee.new(emp_id: 'e11', email: 'compound@test.com', badge_number: 'B555')
@emp11.save
@emp11.add_to_edge_case_company_badge_index(@company3)
@emp11.emp_id
#=> 'e11'

## Update multiple indexed fields atomically
@emp11 = EdgeCaseEmployee.new(emp_id: 'e11', email: 'compound@test.com', badge_number: 'B555')
@emp11.save
@emp11.add_to_edge_case_company_badge_index(@company3)

old_email = @emp11.email
old_badge = @emp11.badge_number
@emp11.email = 'compound_new@test.com'
@emp11.badge_number = 'B666'

# Update both indexes in single transaction
result = EdgeCaseEmployee.transaction do |tx|
  @emp11.update_in_class_email_index(old_email)
  @emp11.update_in_edge_case_company_badge_index(@company3, old_badge)
  'updated'
end
result.successful?
#=> true

## Verify updates succeeded
[EdgeCaseEmployee.find_by_email('compound_new@test.com')&.emp_id, @company3.find_by_badge_number('B666')&.emp_id]
#=> ['e11', 'e11']

## Old values should be gone
[EdgeCaseEmployee.find_by_email('compound@test.com'), @company3.find_by_badge_number('B555')]
#=> [nil, nil]


# Final cleanup
EdgeCaseEmployee.email_index.clear
if @company3&.respond_to?(:badge_index) && @company3.badge_index.respond_to?(:clear)
  @company3.badge_index.clear
end

# Clean up test objects - check if they still exist before destroying
[@company1, @company2, @company3].compact.each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

puts "All edge case tests completed"
