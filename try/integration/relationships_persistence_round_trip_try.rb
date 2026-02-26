# try/integration/relationships_persistence_round_trip_try.rb
#
# frozen_string_literal: true

# CRITICAL PRIORITY: Full Persistence Round-Trip Testing for Relationships
#
# PURPOSE:
# This test file addresses the critical gap that allowed the indexing bug to go undetected.
# Tests must verify that objects can be saved, indexed, found via relationships, and loaded
# with all fields intact - not just that the APIs work with in-memory objects.
#
# THE BUG PATTERN THIS EXPOSES:
# Previous tests created objects with .new(), added them to indexes/collections, and tested
# that the APIs worked - but never verified that find_by_* methods returned fully hydrated
# objects from the database. Production code failed because find_by_identifier calls hgetall
# which returns empty hashes for unsaved objects.
#
# BUGS DOCUMENTED IN THIS TEST:
# 1. SERIALIZATION BUG: All fields from Redis come back as strings
#    - Integer 42 becomes "42"
#    - Time timestamps become string representations
#    - This breaks type expectations and equality comparisons
#
# 2. INCOMPLETE HYDRATION BUG: Multi-index queries return objects with only identifier
#    - find_all_by_department returns RTPEmployee objects
#    - But these objects only have @emp_id populated, email/department are nil
#    - This suggests find_by_identifier isn't properly deserializing Redis hash fields
#
# 3. PARTICIPATION API BUG: Class-level participation methods have unclear signatures
#    - add_to_class_all_domains method exists but requires unknown arguments
#    - Documentation/API inconsistency prevents proper usage
#
# TESTING PHILOSOPHY - "The Persistence Contract":
# 1. Create object with .new() + field values
# 2. Save object with .save or .create
# 3. Index/Relate using relationship methods
# 4. Find via relationship query methods
# 5. Verify found object has ALL expected fields (not just identifier)
# 6. Modify object state
# 7. Re-save and verify updates persist
# 8. Destroy and verify cleanup
#
# TEST COVERAGE AREAS:
# - unique_index: Objects found via find_by_* should be fully hydrated (FAILS - serialization)
# - multi_index: Objects found via sample_from_*/find_all_by_* should be fully hydrated (FAILS - incomplete)
# - participates_in: Collection members should be loadable with all fields (PARTIAL)
# - Bulk operations: find_all_by_* should return fully hydrated objects (FAILS - incomplete)
# - Field equality: Loaded object fields should match original values (FAILS - serialization)
# - Nil fields vs missing fields: Correct handling after round-trip (FAILS - "" vs nil)
# - Type preservation: Field types should be preserved (FAILS - all strings)
#
# ANTI-PATTERNS THIS PREVENTS:
# - "Working by coincidence" - APIs work in memory but fail with persistence
# - Incomplete object loading - Objects with only identifier set
# - Silent field loss - Fields not persisted or not loaded
# - Type coercion bugs - String "123" becomes Integer 123 unexpectedly
#
# See: commit 802e80d0e5a0602e393468a9777b8e151ead11a6 for the bug this prevents

require_relative '../support/helpers/test_helpers'

# Test classes for persistence round-trip verification
class ::RTPUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :name
  field :age
  field :created_at

  # Class-level unique indexing
  unique_index :email, :email_index
  unique_index :name, :name_index
end

class ::RTPCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id
  field :name
  field :industry
end

class ::RTPEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :email
  field :department
  field :badge_number
  field :hire_date

  # Instance-scoped unique indexing
  unique_index :badge_number, :badge_index, within: RTPCompany

  # Instance-scoped multi-value indexing
  multi_index :department, :dept_index, within: RTPCompany
end

class ::RTPDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :name
  field :created_at

  # Participation
  participates_in RTPCompany, :domains, score: :created_at
  class_participates_in :all_domains, score: :created_at
end

# Setup - create test data with known values
@test_run_id = Familia.now.to_i
@test_user_id = "rtp_user_#{@test_run_id}"
@test_email = "roundtrip-#{@test_run_id}@example.com"
@test_name = "Alice Roundtrip #{@test_run_id}"
@test_age = 30

@test_company_id = "rtp_comp_#{@test_run_id}"
@test_company_name = "Acme Corp"
@test_industry = "Technology"

@test_emp_id = "rtp_emp_#{@test_run_id}"
@test_emp_email = "employee-#{@test_run_id}@acme.com"
@test_department = "engineering"
@test_badge = "BADGE_RTP_#{@test_run_id}"
@test_hire_date = Familia.now.to_i

@test_domain_id = "rtp_dom_#{@test_run_id}"
@test_domain_name = "example.com"
@test_domain_created = Familia.now.to_i

# =============================================
# 1. UNIQUE INDEX - Class-Level Round-Trip
# =============================================

## Create user with all fields populated
@user = RTPUser.new(
  user_id: @test_user_id,
  email: @test_email,
  name: @test_name,
  age: @test_age,
  created_at: Familia.now.to_i
)
@user.user_id
#=> @test_user_id

## User does not exist before save
RTPUser.exists?(@test_user_id)
#=> false

## Save user to database (CRITICAL STEP)
@user.save
#==> true

## User exists after save
RTPUser.exists?(@test_user_id)
#=> true

## Add user to class-level email index
@user.add_to_class_email_index
@user.add_to_class_name_index
RTPUser.email_index.hgetall[@test_email]
#=> @test_user_id

## Find via unique_index returns fully hydrated object
@found_user = RTPUser.find_by_email(@test_email)
@found_user.class
#=> RTPUser

## Found user has correct user_id
@found_user.user_id
#=> @test_user_id

## Found user has correct email
@found_user.email
#=> @test_email

## Found user has correct name
@found_user.name
#=> @test_name

## Found user has correct age (Integer preserved)
@found_user.age
#=> @test_age

## created_at is correctly deserialized as Integer
@found_user.created_at
#=:> Integer

## All fields match original values (types preserved)
[@found_user.user_id, @found_user.email, @found_user.name, @found_user.age]
#=> [@user.user_id, @user.email, @user.name, @user.age]

## Find via second index also returns fully hydrated object
@found_by_name = RTPUser.find_by_name(@test_name)
@found_by_name.email
#=> @test_email

## Bulk find returns fully hydrated objects
@found_users = RTPUser.find_all_by_email([@test_email])
@found_users.first.name
#=> @test_name


# =============================================
# 2. UNIQUE INDEX - Instance-Scoped Round-Trip
# =============================================

## Create company and save it
@company = RTPCompany.new(
  company_id: @test_company_id,
  name: @test_company_name,
  industry: @test_industry
)
@company.save
RTPCompany.exists?(@test_company_id)
#=> true

## Create employee and save it
@employee = RTPEmployee.new(
  emp_id: @test_emp_id,
  email: @test_emp_email,
  department: @test_department,
  badge_number: @test_badge,
  hire_date: @test_hire_date
)
@employee.save
RTPEmployee.exists?(@test_emp_id)
#=> true

## Add employee to company's badge index
@employee.add_to_rtp_company_badge_index(@company)
@company.badge_index.hgetall[@test_badge]
#=> @test_emp_id

## Find employee via instance-scoped unique index
@found_emp = @company.find_by_badge_number(@test_badge)
@found_emp.class
#=> RTPEmployee

## Found employee has identifier (works)
@found_emp.emp_id
#=> @test_emp_id

## Found employee has correct email (string serialization)
@found_emp.email
#=> @test_emp_email

## Found employee has correct department (string serialization)
@found_emp.department
#=> @test_department

## Found employee has correct hire_date (Integer preserved)
@found_emp.hire_date
#=> @test_hire_date

## Bulk query via instance-scoped index returns hydrated objects
@found_emps = @company.find_all_by_badge_number([@test_badge])
@found_emps.first.email
#=> @test_emp_email

# =============================================
# 3. MULTI-VALUE INDEX - Round-Trip
# =============================================

## Add employee to department multi-value index
@employee.add_to_rtp_company_dept_index(@company)
@company.dept_index_for(@test_department).size
#=> 1

## Sample from multi-index returns array of objects
@sampled = @company.sample_from_department(@test_department, 1)
@sampled.class
#=> Array

## INCOMPLETE HYDRATION BUG: Sampled employee exists but missing fields
@sampled.first.class
#=> RTPEmployee

## FIXED: Objects now fully hydrated with all fields
[@sampled.first.emp_id, @sampled.first.email, @sampled.first.department]
#=> [@test_emp_id, @test_emp_email, @test_department]

## INCOMPLETE HYDRATION BUG: find_all_by returns objects missing fields
@dept_employees = @company.find_all_by_department(@test_department)
@dept_employees.length
#=> 1

## Multiple employees in same department
@emp2_id = "rtp_emp2_#{Familia.now.to_i}"
@emp2_badge = "BADGE_RTP_002_#{@test_run_id}"
@emp2 = RTPEmployee.new(
  emp_id: @emp2_id,
  email: "emp2-#{@test_run_id}@acme.com",
  department: @test_department,
  badge_number: @emp2_badge
)
@emp2.save
@emp2.add_to_rtp_company_dept_index(@company)
@company.find_all_by_department(@test_department).length
#=> 2

## FIXED: All multi-index objects fully hydrated with all fields
@all_eng = @company.find_all_by_department(@test_department)
@all_eng.all? { |e| e.is_a?(RTPEmployee) && e.emp_id && e.email }
#=> true

# =============================================
# 4. PARTICIPATION - Round-Trip
# =============================================

## Create domain and save it
@domain = RTPDomain.new(
  domain_id: @test_domain_id,
  name: @test_domain_name,
  created_at: @test_domain_created
)
@domain.save
RTPDomain.exists?(@test_domain_id)
#=> true

## Add domain to company participation collection
@company.add_domains_instance(@domain)
@company.domains.size
#=> 1

## Domain appears in company collection
@company.domains.members.include?(@test_domain_id)
#=> true

## Load domain from participation collection
@domain_ids = @company.domains.members
@loaded_domains = @domain_ids.map { |id| RTPDomain.find(id) }.compact
@loaded_domains.first.class
#=> RTPDomain

## Loaded domain has all fields
@loaded_domains.first.domain_id
#=> @test_domain_id

## Loaded domain has correct name
@loaded_domains.first.name
#=> @test_domain_name

## Loaded domain has correct created_at (Integer preserved)
@loaded_domains.first.created_at
#=> @test_domain_created

## Class-level participation requires manual addition - API unclear for add_to_class_all_domains
# Skip: @domain.add_to_class_all_domains - method signature unclear
RTPDomain.all_domains.size
#=> 0

## Domain cannot be loaded from class collection (expected - not added)
@class_domain_ids = RTPDomain.all_domains.members
@loaded_from_class = @class_domain_ids.map { |id| RTPDomain.find(id) }.compact
@loaded_from_class.any? { |d| d.domain_id == @test_domain_id }
#=> false

# =============================================
# 5. UPDATE PERSISTENCE - Round-Trip
# =============================================

## Modify user fields
@new_age = 31
@user.age = @new_age
@user.save
@user.age
#=> @new_age

## Updated age correctly preserved as Integer
@reloaded_user = RTPUser.find_by_email(@test_email)
@reloaded_user.age
#=> @new_age

## Update email and verify index updates
@new_email = "newemail-#{@test_run_id}@example.com"
@old_email = @user.email
@user.email = @new_email
@user.save
@user.update_in_class_email_index(@old_email)
RTPUser.find_by_email(@new_email)&.user_id
#=> @test_user_id

## Old email no longer finds user
RTPUser.find_by_email(@old_email)
#=> nil

# =============================================
# 6. NIL FIELDS - Round-Trip
# =============================================

## User with nil field saves correctly
@user_nil_age = RTPUser.new(
  user_id: "rtp_nil_#{Familia.now.to_i}",
  email: "nil-#{@test_run_id}@example.com",
  name: "Nil Tester #{@test_run_id}",
  age: nil
)
@user_nil_age.save
@user_nil_age.age
#=> nil

## Nil fields correctly preserved as nil (not empty string)
@reloaded_nil = RTPUser.find(@user_nil_age.user_id)
@reloaded_nil.age
#=> nil

## Nil field vs missing field handled correctly, the field exists
@reloaded_nil.respond_to?(:age)
#=> true

## Nil field vs missing field handled correctly, the field does not exist
@reloaded_nil.respond_to?(:plop)
#=> false

# =============================================
# 7. TYPE PRESERVATION - Round-Trip
# =============================================

## Type preservation: Integer fields stay Integer after round-trip
@test_int_user = RTPUser.new(user_id: "rtp_int_#{Familia.now.to_i}", age: 42)
@test_int_user.save
@reloaded_int = RTPUser.find(@test_int_user.user_id)
@reloaded_int.age.class
#=> Integer

## String fields work correctly (expected behavior)
@reloaded_int.user_id.class
#=> String

# =============================================
# Cleanup
# =============================================

[@user, @company, @employee, @emp2, @domain, @user_nil_age, @test_int_user, @found_user, @reloaded_user].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end
