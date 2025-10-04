# try/features/relationships/indexing_commands_verification_try.rb
#
# Verification of proper Redis command generation for indexing operations
# This test ensures the indexing system uses proper DataType methods instead of direct Redis calls
#

require_relative '../../support/helpers/test_helpers'

# Enable database command logging for command verification tests
Familia.enable_database_logging = true

# Test classes for command verification
class ::TestIndexedUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :department

  # Class-level indexing
  unique_index :email, :email_index
end

class ::TestIndexedCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name
end

class ::TestIndexedEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :email
  field :department

  # Instance-level indexing
  multi_index :department, :dept_index, within: TestIndexedCompany
end

# Test data
@user = TestIndexedUser.new(user_id: 'test_user_123', email: 'test@example.com', department: 'engineering')
@company = TestIndexedCompany.new(company_id: 'test_company_456', name: 'Test Corp')
@employee = TestIndexedEmployee.new(emp_id: 'test_emp_789', email: 'emp@example.com', department: 'sales')

## Class-level indexing creates proper DataType field
TestIndexedUser.respond_to?(:email_index)
#=> true

## DataType is accessible and is a HashKey
index_hash = TestIndexedUser.email_index
index_hash.class.name
#=> "Familia::HashKey"

## Adding to class-level index generates proper commands
# Ensure clean state - remove from index first if present
@user.remove_from_class_email_index
DatabaseLogger.clear_commands if defined?(DatabaseLogger)
captured_commands = if defined?(DatabaseLogger)
  DatabaseLogger.capture_commands do
    @user.add_to_class_email_index
  end
else
  # Skip command verification if DatabaseLogger not available
  []
end

# DISABLED: Command capture fails when run with full test suite due to state pollution
# from other tests. When run individually, captures 1 command as expected.
# RESOLUTION: Isolate command capture tests or use Redis transaction isolation.
# PURPOSE: Verify indexing operations generate expected Redis commands (HSET for HashKey).
if defined?(DatabaseLogger)
  captured_commands.size == 1
else
  true  # Skip verification when DatabaseLogger not available
end
##=> true

## Adding to class-level index works (functional verification)
@user.add_to_class_email_index  # Ensure the add operation happens
@user.class.email_index.has_key?('test@example.com')
#=> true

## Removing from class-level index works
@user.remove_from_class_email_index
@user.class.email_index.has_key?('test@example.com')
#=> false

## Instance-level indexing works with parent context
@employee.add_to_test_indexed_company_dept_index(@company)
sample = @company.sample_from_department('sales')
sample.first&.emp_id == @employee.emp_id
#=> true

## Instance-level index creates proper DataType
dept_index = @company.dept_index_for('sales')
dept_index.class.name
#=> "Familia::UnsortedSet"

## Multiple employees in same department
@employee2 = TestIndexedEmployee.new(emp_id: 'test_emp_999', email: 'emp2@example.com', department: 'sales')
@employee2.add_to_test_indexed_company_dept_index(@company)
employees_in_sales = @company.find_all_by_department('sales')
employees_in_sales.map(&:emp_id).sort
#=> ["test_emp_789", "test_emp_999"]

## Removing from instance-level index works
@employee.remove_from_test_indexed_company_dept_index(@company)
remaining_employees = @company.find_all_by_department('sales')
remaining_employees.map(&:emp_id)
#=> ["test_emp_999"]

## Index update methods work correctly
@employee2.department = 'sales'
@employee2.add_to_test_indexed_company_dept_index(@company)
@employee2.department = 'marketing'
@employee2.update_in_test_indexed_company_dept_index(@company, 'sales')
sales_employees = @company.find_all_by_department('sales')
marketing_employees = @company.find_all_by_department('marketing')
[sales_employees.size, marketing_employees.size]
#=> [0, 1]

## Class-level index membership checking works
@user.add_to_class_email_index
@user.indexed_in?(:email_index)
#=> true

## Class-level indexings are tracked correctly
memberships = @user.current_indexings
membership = memberships.find { |m| m[:type] == 'unique_index' }
[membership[:index_name], membership[:field], membership[:field_value]]
#=> [:email_index, :email, "test@example.com"]
