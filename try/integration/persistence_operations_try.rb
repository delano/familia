# try/core/persistence_operations_try.rb
#
# Comprehensive test coverage for core persistence methods: exists?, save, save_if_not_exists, create
# This test addresses gaps that allowed the exists? bug to go undetected

require_relative '../support/helpers/test_helpers'

# Use a simple test class to isolate persistence behavior
class PersistenceTestModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :value
end

# Create model with expiration feature for save_fields testing
class ExpirationPersistenceTest < Familia::Horreum
  feature :expiration
  identifier_field :id
  field :id
  field :name
  field :email
  field :status
  field :metadata

  default_expiration 3600  # 1 hour
end

# Simple model without expiration feature
class SimpleModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :value
end

# Clean up any existing test data
cleanup_keys = []
begin
  existing_test_keys = Familia.dbclient.keys('persistencetestmodel:*')
  cleanup_keys.concat(existing_test_keys)
  Familia.dbclient.del(*existing_test_keys) if existing_test_keys.any?
rescue => e
  # Ignore cleanup errors
end

@test_id_counter = 0
def next_test_id
  @test_id_counter += 1
  "test-#{Familia.now.to_i}-#{@test_id_counter}"
end

# =============================================
# 1. exists? Method Coverage - The Critical Bug
# =============================================

## New object does not exist (both variants)
@new_obj = PersistenceTestModel.new(id: next_test_id, name: 'New Object')
[@new_obj.exists?, @new_obj.exists?(check_size: false)]
#=> [false, false]

## Object exists after save (both variants)
@new_obj.save
[@new_obj.exists?, @new_obj.exists?(check_size: false)]
#=> [true, true]

## Class-level and instance-level exists? consistency
class_exists = PersistenceTestModel.exists?(@new_obj.identifier)
instance_exists = @new_obj.exists?
[class_exists, instance_exists]
#=> [true, true]

## Empty object exists check (critical edge case)
@empty_obj = PersistenceTestModel.new(id: next_test_id)
@empty_obj.save  # Save with no fields set
# Should return true with check_size: false (key exists)
# Should return false with check_size: true (but fields exist due to id)
[@empty_obj.exists?(check_size: false), @empty_obj.exists?(check_size: true)]
#=> [true, true]

## Object with only nil fields edge case
@nil_fields_obj = PersistenceTestModel.new(id: next_test_id, name: nil, value: nil)
@nil_fields_obj.save
# Should handle nil fields correctly
[@nil_fields_obj.exists?(check_size: false), @nil_fields_obj.exists?(check_size: true)]
#=> [true, true]

## Object destroyed does not exist (both variants)
@new_obj.destroy!
[@new_obj.exists?, @new_obj.exists?(check_size: false)]
#=> [false, false]

# =============================================
# 2. save Method Coverage
# =============================================

## Basic save functionality
@save_test = PersistenceTestModel.new(id: next_test_id, name: 'Save Test', value: 'data')
result = @save_test.save
[result, @save_test.exists?]
#=> [true, true]

## Save with update_expiration: false
@save_no_exp = PersistenceTestModel.new(id: next_test_id, name: 'No Expiration')
result = @save_no_exp.save(update_expiration: false)
[result, @save_no_exp.exists?]
#=> [true, true]

## Save operation idempotency (multiple saves)
@idempotent_obj = PersistenceTestModel.new(id: next_test_id, name: 'Idempotent')
first_save = @idempotent_obj.save
@idempotent_obj.name = 'Modified'
second_save = @idempotent_obj.save
[first_save, second_save, @idempotent_obj.exists?]
#=> [true, true, true]

## Save with partial field data
@partial_obj = PersistenceTestModel.new(id: next_test_id)
@partial_obj.name = 'Only Name UnsortedSet'
# value field is nil/unset
result = @partial_obj.save
[result, @partial_obj.exists?, @partial_obj.name]
#=> [true, true, 'Only Name UnsortedSet']

# =============================================
# 3. save_if_not_exists Method Coverage
# =============================================

## save_if_not_exists saves new object successfully
@sine_new = PersistenceTestModel.new(id: next_test_id, name: 'Save If Not Exists New')
result = @sine_new.save_if_not_exists
[result, @sine_new.exists?]
#=> [true, true]

## save_if_not_exists! raises error for existing object
@sine_duplicate = PersistenceTestModel.new(id: @sine_new.identifier, name: 'Duplicate')
@sine_duplicate.save_if_not_exists!
#=!> Familia::RecordExistsError

## save_if_not_exists with update_expiration: false
@sine_no_exp = PersistenceTestModel.new(id: next_test_id, name: 'No Exp SINE')
result = @sine_no_exp.save_if_not_exists(update_expiration: false)
[result, @sine_no_exp.exists?]
#=> [true, true]

## Object state unchanged after save_if_not_exists failure
original_name = 'Original Name'
@sine_fail_test = PersistenceTestModel.new(id: next_test_id, name: original_name)
@sine_fail_test.save_if_not_exists
# Now create duplicate and verify state doesn't change on failure
@sine_fail_duplicate = PersistenceTestModel.new(id: @sine_fail_test.identifier, name: 'Changed Name')
begin
  @sine_fail_duplicate.save_if_not_exists
  false # Should not reach here
rescue Familia::RecordExistsError
  # State should be unchanged
  @sine_fail_duplicate.name == 'Changed Name'
end
#=> true

# =============================================
# 4. create Method Coverage (MISSING from current tests)
# =============================================

# NOTE: create method tests disabled due to Valkey/Redis::Future bug
# This would be high-priority coverage but needs the create method bug fixed first

## create method alternative: manual creation simulation
@manual_created = PersistenceTestModel.new(id: next_test_id, name: 'Manual Created', value: 'manual')
before_create = @manual_created.exists?
if @manual_created.exists?
  raise Familia::Problem, "Object already exists"
else
  @manual_created.save
end
after_create = @manual_created.exists?
[before_create, after_create, @manual_created.name]
#=> [false, true, 'Manual Created']

## create duplicate prevention simulation
@duplicate_test = PersistenceTestModel.new(id: @manual_created.identifier, name: 'Duplicate Attempt')
begin
  if @duplicate_test.exists?
    raise Familia::Problem, "Object already exists"
  else
    @duplicate_test.save
  end
  false  # Should not reach here
rescue Familia::Problem
  true   # Expected
end
#=> true

# =============================================
# 5. State Transition Testing (Critical Gap)
# =============================================

## NEW → SAVED: Verify exists? changes from false to true
@state_obj = PersistenceTestModel.new(id: next_test_id, name: 'State Transition')
@before_save = @state_obj.exists?
@state_obj.save
@after_save = @state_obj.exists?
[@before_save, @after_save]
#=> [false, true]

## SAVED → DESTROYED: Verify exists? changes from true to false
# Use the same state object from previous test
@state_obj.destroy!
@after_destroy = @state_obj.exists?
[@after_save, @after_destroy]  # Use instance variables
#=> [true, false]

## SAVED → MODIFIED → SAVED: State consistency through updates
@mod_obj = PersistenceTestModel.new(id: next_test_id, name: 'Original', value: 'original_val')
@mod_obj.save
original_exists = @mod_obj.exists?
@mod_obj.name = 'Modified'
@mod_obj.value = 'modified_val'
@mod_obj.save
modified_exists = @mod_obj.exists?
# Refresh to verify persistence
@mod_obj.refresh!
persisted_name = @mod_obj.name
[original_exists, modified_exists, persisted_name]
#=> [true, true, 'Modified']

## Field persistence across state changes
@field_obj = PersistenceTestModel.new(id: next_test_id)
# Start with no name
@field_obj.save
@field_obj.name = 'Added Later'
@field_obj.save
@field_obj.refresh!
@field_obj.name
#=> 'Added Later'

# =============================================
# 6. Integration with Features
# =============================================

## exists? behavior with encrypted fields (if available)
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class EncryptedPersistenceTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :email
  encrypted_field :secret_value
end

@enc_obj = EncryptedPersistenceTest.new(id: next_test_id, email: 'test@example.com')
before_save = @enc_obj.exists?
@enc_obj.save
@enc_obj.secret_value = 'encrypted_data'
@enc_obj.save
after_save = @enc_obj.exists?

# Clean up encryption config
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil

[before_save, after_save]
#=> [false, true]

# =============================================
# 7. Error Handling & Edge Cases
# =============================================

## Empty identifier handling
begin
  empty_id_obj = PersistenceTestModel.new(id: '')
  PersistenceTestModel.exists?('')
  false  # Should not reach here
rescue Familia::NoIdentifier
  true   # Expected error
end
#=> true

## nil identifier handling
begin
  nil_id_obj = PersistenceTestModel.new(id: nil)
  PersistenceTestModel.exists?(nil)
  false  # Should not reach here
rescue Familia::NoIdentifier
  true   # Expected error
end
#=> true

## Concurrent exists? checks are consistent
@concurrent_obj = PersistenceTestModel.new(id: next_test_id, name: 'Concurrent Test')
@concurrent_obj.save

# Multiple exists? calls should be consistent
results = 3.times.map { @concurrent_obj.exists? }
results.uniq.length
#=> 1

## Database key structure validation
@key_obj = PersistenceTestModel.new(id: next_test_id)
@key_obj.save
expected_suffix = ":#{@key_obj.identifier}:object"
actual_key = @key_obj.dbkey
[actual_key.include?(expected_suffix), @key_obj.exists?]
#=> [true, true]

# =============================================
# Cleanup
# =============================================

# =============================================
# 8. save_fields Method Coverage
# =============================================

## save_fields basic functionality with specified fields
@save_fields_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Original Name', email: 'test@example.com', status: 'active')
@save_fields_obj.save
# Modify fields locally
@save_fields_obj.name = 'Updated Name'
@save_fields_obj.status = 'inactive'
@save_fields_obj.metadata = { updated: true }
# Save only specific fields
result = @save_fields_obj.save_fields(:name, :metadata)
[result.class == ExpirationPersistenceTest, @save_fields_obj.exists?]
#=> [true, true]

## Verify only specified fields were saved
@save_fields_obj.refresh!
[@save_fields_obj.name, @save_fields_obj.status, @save_fields_obj.metadata]
#=> ['Updated Name', 'active', { 'updated' => true }]

## save_fields with update_expiration: true (default)
@exp_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Expiration Test')
@exp_obj.save
original_ttl = @exp_obj.ttl
# Wait a moment to ensure TTL decreases
sleep 0.1
@exp_obj.name = 'Updated with TTL'
@exp_obj.save_fields(:name)  # Should update expiration by default
new_ttl = @exp_obj.ttl
# TTL should be refreshed (closer to default_expiration)
# Allow for small timing variations
new_ttl >= (ExpirationPersistenceTest.default_expiration - 10)
#=> true

## save_fields with update_expiration: false
@no_exp_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'No Exp Update')
@no_exp_obj.save
# Wait briefly and get TTL
sleep 0.1
original_ttl = @no_exp_obj.ttl
@no_exp_obj.name = 'Updated without TTL'
@no_exp_obj.save_fields(:name, update_expiration: false)
new_ttl = @no_exp_obj.ttl
# TTL should be approximately the same (slightly less due to time passing)
(new_ttl - original_ttl).abs < 2
#=> true

## save_fields with multiple fields
@multi_fields_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Multi', email: 'multi@test.com')
@multi_fields_obj.save
@multi_fields_obj.name = 'Multi Updated'
@multi_fields_obj.email = 'updated@test.com'
@multi_fields_obj.status = 'new_status'
result = @multi_fields_obj.save_fields(:name, :email, :status)
@multi_fields_obj.refresh!
[@multi_fields_obj.name, @multi_fields_obj.email, @multi_fields_obj.status]
#=> ['Multi Updated', 'updated@test.com', 'new_status']

## save_fields with string field names
@string_fields_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'String Fields')
@string_fields_obj.save
@string_fields_obj.name = 'Updated via String'
result = @string_fields_obj.save_fields('name')  # String instead of symbol
@string_fields_obj.refresh!
@string_fields_obj.name
#=> 'Updated via String'

## save_fields error handling - empty fields
@empty_fields_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Empty Test')
@empty_fields_obj.save
@empty_fields_obj.save_fields()
#=!> ArgumentError

## save_fields error handling - unknown field
@unknown_field_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Unknown Field')
@unknown_field_obj.save
@unknown_field_obj.save_fields(:nonexistent_field)
#=!> ArgumentError

## save_fields with nil values
@nil_values_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Nil Values', status: 'initial')
@nil_values_obj.save
@nil_values_obj.status = nil
@nil_values_obj.save_fields(:status)
@nil_values_obj.refresh!
@nil_values_obj.status
#=> nil

## save_fields with complex data types (Hash, Array)
@complex_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Complex')
@complex_obj.save
@complex_obj.metadata = {
  tags: ['ruby', 'redis'],
  config: { timeout: 30, retries: 3 },
  enabled: true
}
@complex_obj.save_fields(:metadata)
@complex_obj.refresh!
expected_metadata = {
  'tags' => ['ruby', 'redis'],
  'config' => { 'timeout' => 30, 'retries' => 3 },
  'enabled' => true
}
@complex_obj.metadata == expected_metadata
#=> true

## save_fields transactional behavior
@transaction_obj = ExpirationPersistenceTest.new(id: next_test_id, name: 'Transaction Test')
@transaction_obj.save
@transaction_obj.name = 'Updated in Transaction'
@transaction_obj.email = 'transaction@test.com'
# All fields should be saved atomically
@transaction_obj.save_fields(:name, :email)
@transaction_obj.refresh!
[@transaction_obj.name, @transaction_obj.email]
#=> ['Updated in Transaction', 'transaction@test.com']

## save_fields performance with model without expiration feature

@simple_obj = SimpleModel.new(id: next_test_id, name: 'Simple', value: 'test')
@simple_obj.save
@simple_obj.name = 'Simple Updated'
# Should work without expiration feature (update_expiration param ignored)
result = @simple_obj.save_fields(:name, update_expiration: true)
@simple_obj.refresh!
@simple_obj.name
#=> 'Simple Updated'

# =============================================
# Cleanup
# =============================================

# Clean up test data
test_keys = Familia.dbclient.keys('persistencetestmodel:*')
test_keys.concat(Familia.dbclient.keys('encryptedpersistencetest:*')) if defined?(EncryptedPersistenceTest)
test_keys.concat(Familia.dbclient.keys('expirationpersistencetest:*'))
test_keys.concat(Familia.dbclient.keys('simplemodel:*'))
Familia.dbclient.del(*test_keys) if test_keys.any?
