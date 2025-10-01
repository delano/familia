# try/features/relationships/indexing_try.rb
#
# Comprehensive tests for Familia indexing relationships functionality
# Tests both multi_index (parent-context) and unique_index (class-level) indexing
#

require_relative '../../helpers/test_helpers'

# Test classes for indexing functionality
class ::TestUser < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :user_id
  field :user_id
  field :email
  field :username
  field :department
  field :role

  # Class-level unique indexing
  unique_index :email, :email_lookup
  unique_index :username, :username_lookup, query: false
end

class ::TestCompany < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :company_id
  field :company_id
  field :name

  unsorted_set :employees
end

class ::TestEmployee < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :emp_id
  field :emp_id
  field :email
  field :department
  field :manager_id

  # Instance-scoped multi-value indexing
  multi_index :department, :dept_index, within: TestCompany
  multi_index :email, :email_index, within: TestCompany, query: false
end

# Setup
@user1 = TestUser.new(user_id: 'user_001', email: 'alice@example.com', username: 'alice', department: 'engineering', role: 'developer')
@user2 = TestUser.new(user_id: 'user_002', email: 'bob@example.com', username: 'bob', department: 'marketing', role: 'manager')
@user3 = TestUser.new(user_id: 'user_003', email: 'charlie@example.com', username: 'charlie', department: 'engineering', role: 'lead')

@company_id = "comp_#{rand(10000000)}"
@company = TestCompany.create(company_id: @company_id, name: 'Acme Corp')
@emp1 = TestEmployee.new(emp_id: 'emp_001', email: 'alice@acme.com', department: 'engineering', manager_id: 'mgr_001')
@emp2 = TestEmployee.new(emp_id: 'emp_002', email: 'bob@acme.com', department: 'sales', manager_id: 'mgr_002')


## Context-scoped methods require context parameter
@emp2.add_to_test_company_dept_index(@company)
sample = @company.sample_from_department(@emp2.department)
[sample.first&.emp_id, @emp2.emp_id]
#=> ["emp_002", "emp_002"]


# =============================================
# 1. Class-Level Indexing (unique_index) Tests
# =============================================

## Class indexing relationships are properly registered
@user1.class.indexing_relationships.length
#=> 2

## First indexing relationship has correct configuration
config = @user1.class.indexing_relationships.first
[config.field, config.index_name, config.target_class == TestUser, config.query]
#=> [:email, :email_lookup, true, true]

## Second indexing relationship has query disabled
config = @user1.class.indexing_relationships.last
[config.field, config.index_name, config.query]
#=> [:username, :username_lookup, false]

## Class-level query methods are generated for email
TestUser.respond_to?(:find_by_email)
#=> true

## Class-level bulk query methods are generated
TestUser.respond_to?(:find_all_by_email)
#=> true

## Index hash accessor method is generated
TestUser.respond_to?(:email_lookup)
#=> true

## Index rebuild method is generated
TestUser.respond_to?(:rebuild_email_lookup)
#=> true

## No query methods generated when query: false
TestUser.respond_to?(:find_by_username)
#=> false

## Instance methods for class indexing are generated
@user1.respond_to?(:add_to_class_email_lookup)
#=> true

## Update methods for class indexing are generated
@user1.respond_to?(:update_in_class_email_lookup)
#=> true

## Remove methods for class indexing are generated
@user1.respond_to?(:remove_from_class_email_lookup)
#=> true

## User can be added to class index manually
@user1.add_to_class_email_lookup
user = TestUser.find_by_email(@user1.email)
user.user_id
#=> "user_001"

## Index lookup works via hash access
TestUser.email_lookup['alice@example.com']
#=> "user_001"

## Class query method works
found_user = TestUser.find_by_email('alice@example.com')
found_user&.user_id
#=> "user_001"

## Multiple users can be indexed
@user2.add_to_class_email_lookup
@user3.add_to_class_email_lookup
TestUser.email_lookup.length
#=> 3

## Bulk query returns multiple users
emails = ['alice@example.com', 'bob@example.com']
found_users = TestUser.find_all_by_email(emails)
found_users.map(&:user_id).sort
#=> ["user_001", "user_002"]

## Empty array for bulk query with empty input
TestUser.find_all_by_email([]).length
#=> 0

## Update index entry with old value removal
old_email = @user1.email
@user1.email = 'alice.new@example.com'
@user1.update_in_class_email_lookup(old_email)
[TestUser.email_lookup[old_email], TestUser.email_lookup[@user1.email]]
#=> [nil, "user_001"]

## Remove from class index
@user1.remove_from_class_email_lookup
TestUser.email_lookup[@user1.email]
#=> nil

## Username index works without query methods (query: false)
@user1.add_to_class_username_lookup
TestUser.respond_to?(:find_by_username)
#=> false

# =============================================
# 2. Context-Scoped Indexing (multi_index) Tests
# =============================================

## Context-scoped indexing relationships are registered
@emp1.class.indexing_relationships.length
#=> 2

## Context-scoped relationship has correct configuration
config = @emp1.class.indexing_relationships.first
[config.field, config.index_name, config.target_class, config.target_class_name]
#=> [:department, :dept_index, TestCompany, "TestCompany"]

## Context-scoped methods are generated with collision-free naming
@emp1.respond_to?(:add_to_test_company_dept_index)
#=> true

## Context-scoped update methods are generated
@emp1.respond_to?(:update_in_test_company_dept_index)
#=> true

## Context-scoped remove methods are generated
@emp1.respond_to?(:remove_from_test_company_dept_index)
#=> true

## Instance sampling methods are generated on context class
@company.respond_to?(:sample_from_department)
#=> true

## Instance bulk query methods are generated on context class
@company.respond_to?(:find_all_by_department)
#=> true

## Index accessor method is generated on context class
@company.respond_to?(:dept_index_for)
#=> true

## Employee can be added to company department index
@emp1.add_to_test_company_dept_index(@company)
sample = @company.sample_from_department(@emp1.department)
sample.first&.emp_id
#=> "emp_001"

## Context instance sampling method works
sample = @company.sample_from_department('engineering')
sample.first&.emp_id
#=> "emp_001"

## Multiple employees in same department (one-to-many)
@emp2.department = 'engineering'
@emp2.add_to_test_company_dept_index(@company)
employees = @company.find_all_by_department('engineering')
employees.length
#=> 2

## Sample with count parameter returns array of specified size
sample = @company.sample_from_department('engineering', 2)
sample.length
#=> 2

## Sample without count parameter defaults to 1
sample = @company.sample_from_department('engineering')
sample.length
#=> 1

## Update context-scoped index entry
old_dept = @emp1.department
@emp1.department = 'research'
@emp1.update_in_test_company_dept_index(@company, old_dept)
engineering_emps = @company.find_all_by_department('engineering')
research_emps = @company.find_all_by_department('research')
[engineering_emps.length, research_emps.length]
#=> [1, 1]

## Remove from context-scoped index
@emp1.remove_from_test_company_dept_index(@company)
research_emps = @company.find_all_by_department('research')
research_emps.length
#=> 0

## Query methods respect query: false setting
@company.respond_to?(:find_by_email)
#=> false

# =============================================
# 3. Instance Helper Methods Tests
# =============================================

## Update all indexes helper method exists
@user1.respond_to?(:update_all_indexes)
#=> true

## Remove from all indexes helper method exists
@user1.respond_to?(:remove_from_all_indexes)
#=> true

## Current indexings query method exists
@user1.respond_to?(:current_indexings)
#=> true

## Indexed in check method exists
@user1.respond_to?(:indexed_in?)
#=> true

## Add user back to index for membership tests
@user1.email = 'alice@example.com'
@user1.add_to_class_email_lookup
@user1.indexed_in?(:email_lookup)
#=> true

## User not indexed in non-existent index
@user1.indexed_in?(:nonexistent_index)
#=> false

## Current indexings returns correct information
memberships = @user1.current_indexings
membership = memberships.find { |m| m[:index_name] == :email_lookup }
[membership[:type], membership[:field], membership[:field_value]]
#=> ["unique_index", :email, "alice@example.com"]

## Update all indexes with old values (class-level only)
old_values = { email: 'alice@example.com' }
@user1.email = 'alice.updated@example.com'
@user1.update_all_indexes(old_values)
[TestUser.email_lookup['alice@example.com'], TestUser.email_lookup[@user1.email]]
#=> [nil, "user_001"]

## Remove from all indexes (class-level only)
@user1.remove_from_all_indexes
TestUser.email_lookup[@user1.email]
#=> nil

## Context-scoped indexes require context parameter for updates
@emp2.add_to_test_company_dept_index(@company)
@emp2.update_all_indexes({}, @company)
sample = @company.sample_from_department(@emp2.department)
sample.first&.emp_id
#=> "emp_002"

# =============================================
# 4. Edge Cases and Error Handling
# =============================================

## Query returns nil for non-existent key
TestUser.find_by_email('nonexistent@example.com')
#=> nil

## Bulk query handles mixed existing/non-existing keys
emails = ['bob@example.com', 'nonexistent@example.com']
found = TestUser.find_all_by_email(emails)
found.map(&:user_id)
#=> ["user_002"]

## Adding to index with nil field value does nothing
@user_nil = TestUser.new(user_id: 'user_nil', email: nil)
@user_nil.add_to_class_email_lookup
TestUser.find_by_email('')
#=> nil

## Update with nil new value removes from index
@user2.email = nil
@user2.update_in_class_email_lookup('bob@example.com')
TestUser.email_lookup['bob@example.com']
#=> nil

## Current indexings returns empty array when no indexes
@user_nil.current_indexings.length
#=> 0

# Teardown
# Clean up indexes
# TestUser.email_lookup.delete!
# TestCompany.dept_index.delete!
# TestCompany.email_index.delete!

# # Clean up objects
# [@user1, @user2, @user3, @company, @emp1, @emp2].each do |obj|
#   obj.destroy if obj.respond_to?(:destroy) && obj.respond_to?(:exists?) && obj.exists?
# end
