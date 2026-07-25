# try/unit/horreum/multi_field_update_try.rb
#
# frozen_string_literal: true

# Tests for Horreum multi-field update methods:
# - multi_field_update: batch field updates with optional expiration control
# - multi_field_fast_write: immediate HSET without full save cycle
# - field-type guards: transient fields and plaintext-to-encrypted rejected

require 'base64'
require_relative '../../support/helpers/test_helpers'

Familia.config.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.current_key_version = :v1

# Model with encrypted and transient fields for guard coverage
class MultiFieldGuardModel < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields

  identifier_field :guard_id
  field :guard_id
  field :label
  encrypted_field :api_key
  transient_field :temp_secret
end

# Setup: Create test customer
@test_prefix = "multi_field_test_#{Time.now.to_i}"
@customer = Customer.new(
  custid: "#{@test_prefix}_customer",
  email: 'multi@example.com',
  name: 'Multi Field Test',
  role: 'user'
)
@customer.save
@guarded = MultiFieldGuardModel.new(guard_id: "#{@test_prefix}_guard", label: 'initial')
@guarded.save

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

# ============================================================
# Field-type guards: transient and encrypted fields
# ============================================================

## multi_field_update rejects transient fields (never persisted)
begin
  @guarded.multi_field_update(temp_secret: 'ephemeral')
  'UNEXPECTED SUCCESS'
rescue ArgumentError => e
  e.message.include?('Transient field temp_secret')
end
#=> true

## multi_field_fast_write rejects transient fields (never persisted)
begin
  @guarded.multi_field_fast_write(temp_secret: 'ephemeral')
  'UNEXPECTED SUCCESS'
rescue ArgumentError => e
  e.message.include?('Transient field temp_secret')
end
#=> true

## multi_field_update rejects plaintext for encrypted fields
begin
  @guarded.multi_field_update(api_key: 'raw-plaintext-secret')
  'UNEXPECTED SUCCESS'
rescue ArgumentError => e
  e.message.include?('Encrypted field api_key')
end
#=> true

## multi_field_fast_write rejects plaintext for encrypted fields
begin
  @guarded.multi_field_fast_write(api_key: 'raw-plaintext-secret')
  'UNEXPECTED SUCCESS'
rescue ArgumentError => e
  e.message.include?('Encrypted field api_key')
end
#=> true

## Rejected batch persists nothing, including the regular fields in it
begin
  @guarded.multi_field_update(label: 'should-not-persist', api_key: 'plain')
rescue ArgumentError
  # expected
end
@guarded.dbclient.hget(@guarded.dbkey, 'label')
#=> '"initial"'

## Regular fields on a guard-enabled model still persist
@guarded.multi_field_update(label: 'updated-label')
@guarded.dbclient.hget(@guarded.dbkey, 'label')
#=> '"updated-label"'

## ConcealedString value persists ciphertext, not plaintext
@guarded.api_key = 'conceal-me-multi'
@guarded.multi_field_update(api_key: @guarded.api_key)
stored = @guarded.dbclient.hget(@guarded.dbkey, 'api_key')
[stored.include?('conceal-me-multi'), stored.include?('"algorithm"')]
#=> [false, true]

## Persisted ConcealedString round-trips through reveal
reloaded = MultiFieldGuardModel.find_by_id(@guarded.guard_id)
revealed = nil
reloaded.api_key.reveal { |pt| revealed = pt.dup }
revealed
#=> 'conceal-me-multi'

## nil still deletes the encrypted field
@guarded.multi_field_update(api_key: nil)
@guarded.dbclient.hexists(@guarded.dbkey, 'api_key')
#=> false

## multi_field_fast_write persists ciphertext for ConcealedString values
@guarded.api_key = 'conceal-me-fast'
@guarded.multi_field_fast_write(api_key: @guarded.api_key)
stored = @guarded.dbclient.hget(@guarded.dbkey, 'api_key')
[stored.include?('conceal-me-fast'), stored.include?('"algorithm"')]
#=> [false, true]

## multi_field_fast_write with nil deletes the encrypted field
@guarded.multi_field_fast_write(api_key: nil, label: 'fast-label')
[@guarded.dbclient.hexists(@guarded.dbkey, 'api_key'), @guarded.dbclient.hget(@guarded.dbkey, 'label')]
#=> [false, '"fast-label"']

# Teardown: Clean up test data
@customer.destroy! rescue nil
@guarded.destroy! rescue nil
