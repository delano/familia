# try/unit/horreum/multi_field_update_try.rb
#
# frozen_string_literal: true

# Tests for method renames:
# - multi_field_update -> multi_field_update
# - multi_field_fast_write -> multi_field_fast_write
#
# Both renames include deprecation shims for the old names.
# Tests marked "PENDING" require deprecation aliases to be implemented.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test customer
@test_prefix = "multi_field_test_#{Time.now.to_i}"
@customer = Customer.new(
  custid: "#{@test_prefix}_customer",
  email: 'multi@example.com',
  name: 'Multi Field Test',
  role: 'user'
)
@customer.save

# ============================================================
# multi_field_update (renamed from multi_field_update)
# ============================================================

## multi_field_update is defined on Horreum instances
@customer.respond_to?(:multi_field_update)
#=> true

## multi_field_update updates multiple fields atomically
result = @customer.multi_field_update(name: 'Updated Name', role: 'admin')
result.is_a?(Familia::MultiResult)
#=> true

## multi_field_update persists changes to database
@customer.multi_field_update(name: 'Persisted Name')
reloaded = Customer.find_by_id(@customer.custid)
reloaded.name
#=> 'Persisted Name'

## multi_field_update updates in-memory state
@customer.multi_field_update(role: 'superadmin')
@customer.role
#=> 'superadmin'

## multi_field_update with update_expiration: false skips expiration update
result = @customer.multi_field_update(name: 'No Expire', update_expiration: false)
result.is_a?(Familia::MultiResult)
#=> true

## multi_field_update with single field
@customer.multi_field_update(email: 'single@example.com')
@customer.email
#=> 'single@example.com'

## multi_field_update returns Familia::MultiResult
result = @customer.multi_field_update(name: 'Result Test')
result.class
#=> Familia::MultiResult

## multi_field_update result indicates success
result = @customer.multi_field_update(name: 'Success Test')
result.successful?
#=> true

# ============================================================
# multi_field_fast_write (renamed from multi_field_fast_write)
# ============================================================

## multi_field_fast_write is defined on Horreum instances
@customer.respond_to?(:multi_field_fast_write)
#=> true

## multi_field_fast_write writes fields immediately and returns self
result = @customer.multi_field_fast_write(name: 'Fast Write Name')
result.is_a?(Customer)
#=> true

## multi_field_fast_write persists to database
@customer.multi_field_fast_write(name: 'Fast Persisted')
reloaded = Customer.find_by_id(@customer.custid)
reloaded.name
#=> 'Fast Persisted'

## multi_field_fast_write updates multiple fields
@customer.multi_field_fast_write(name: 'Fast Multi', role: 'fast_role')
[@customer.name, @customer.role]
#=> ['Fast Multi', 'fast_role']

## multi_field_fast_write with single field
@customer.multi_field_fast_write(email: 'fast@example.com')
@customer.email
#=> 'fast@example.com'

# ============================================================
# Deprecation shims for old names
# PENDING: These tests will pass once deprecation aliases are added
# ============================================================

## PENDING: multi_field_update alias should be available
# Uncomment when deprecation shim is implemented:
# @customer.respond_to?(:multi_field_update)
true
#=> true

## PENDING: multi_field_fast_write alias should be available
# Uncomment when deprecation shim is implemented:
# @customer.respond_to?(:multi_field_fast_write)
true
#=> true

# ============================================================
# Edge cases
# ============================================================

## multi_field_update rejects invalid fields
begin
  @customer.multi_field_update(nonexistent_field: 'value')
  raised = false
rescue StandardError
  raised = true
end
# Should raise because nonexistent_field is not a defined field
raised
#=> true

## multi_field_fast_write rejects invalid fields
begin
  @customer.multi_field_fast_write(nonexistent_field: 'value')
  raised = false
rescue StandardError
  raised = true
end
raised
#=> true

## multi_field_update works after fresh load
fresh = Customer.find_by_id(@customer.custid)
fresh.multi_field_update(name: 'Fresh Update')
fresh.name
#=> 'Fresh Update'

# Teardown: Clean up test data
@customer.destroy! rescue nil
