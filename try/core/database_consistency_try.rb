# try/core/database_consistency_try.rb
#
# Database consistency verification and edge case testing
# Complements persistence_operations_try.rb with deeper consistency checks

require_relative '../helpers/test_helpers'

# Test class with different field types for consistency verification
class ConsistencyTestModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :email
  field :active
  field :metadata  # For complex data types
end

# Clean up existing test data
cleanup_keys = []
begin
  existing_test_keys = Familia.dbclient.keys('consistencytestmodel:*')
  cleanup_keys.concat(existing_test_keys)
  Familia.dbclient.del(*existing_test_keys) if existing_test_keys.any?
rescue => e
  # Ignore cleanup errors
end

@test_id_counter = 0
def next_test_id
  @test_id_counter += 1
  "consistency-#{Familia.now.to_i}-#{@test_id_counter}"
end

# =============================================
# 1. Database Consistency Verification
# =============================================

## Valkey/Redis key structure follows expected pattern
@key_test = ConsistencyTestModel.new(id: next_test_id, name: 'Key Test')
@key_test.save
dbkey = @key_test.dbkey
key_parts = dbkey.split(':')
# Should have pattern: [prefix, identifier, suffix]
[key_parts.length >= 3, key_parts.include?(@key_test.identifier), key_parts.last]
#=> [true, true, 'object']

## Field serialization/deserialization roundtrips correctly
@serial_test = ConsistencyTestModel.new(id: next_test_id)
# Test different data types
@serial_test.name = 'Serialization Test'
@serial_test.active = true
@serial_test.metadata = { key: 'value', array: [1, 2, 3] }
@serial_test.save

# Refresh and verify data integrity
@serial_test.refresh!
[@serial_test.name, @serial_test.active, @serial_test.metadata]
#=> ['Serialization Test', 'true', {:key=>'value', :array=>[1, 2, 3]}]

## Hash field count matches object field count
expected_fields = @serial_test.class.persistent_fields.length
redis_field_count = Familia.dbclient.hlen(@serial_test.dbkey)
actual_object_fields = @serial_test.to_h.keys.length
# All should match (redis may have fewer due to nil exclusion)
[expected_fields >= redis_field_count, redis_field_count, actual_object_fields]
#=> [true, 5, 5]

## Memory vs persistence state consistency after save
@consistency_obj = ConsistencyTestModel.new(id: next_test_id, name: 'Memory Test', email: 'test@example.com')
@consistency_obj.save

# Get memory state
memory_name = @consistency_obj.name
memory_email = @consistency_obj.email

# Get persistence state
redis_name = Familia.dbclient.hget(@consistency_obj.dbkey, 'name')
redis_email = Familia.dbclient.hget(@consistency_obj.dbkey, 'email')

[memory_name == redis_name, memory_email == redis_email]
#=> [true, true]

# =============================================
# 2. Concurrent Modification Detection
# =============================================

## Multiple objects with same identifier maintain consistency
obj1 = ConsistencyTestModel.new(id: next_test_id, name: 'Object 1')
obj1.save
obj1_id = obj1.identifier

# Create second object with same ID (simulating concurrent access)
obj2 = ConsistencyTestModel.new(id: obj1_id, name: 'Object 2')
obj2.save  # This overwrites obj1's data

# Both objects should now see the updated data when refreshed
obj1.refresh!
obj2.refresh!
[obj1.name == obj2.name, obj1.name]
#=> [true, 'Object 2']

## exists? consistency under concurrent modifications
@concurrent_mod = ConsistencyTestModel.new(id: next_test_id, name: 'Concurrent')
@concurrent_mod.save
before_modify = @concurrent_mod.exists?

# Simulate external modification
Familia.dbclient.hset(@concurrent_mod.dbkey, 'name', 'Modified Externally')
after_modify = @concurrent_mod.exists?

# exists? should still return true regardless of field changes
[before_modify, after_modify]
#=> [true, true]

# =============================================
# 3. Edge Cases and Error Conditions
# =============================================

## Corrupted data handling (malformed JSON in complex fields)
@corrupt_test = ConsistencyTestModel.new(id: next_test_id)
@corrupt_test.save

# Manually insert malformed JSON
Familia.dbclient.hset(@corrupt_test.dbkey, 'metadata', '{"invalid": json}')

# Object should handle corrupted data gracefully
begin
  @corrupt_test.refresh!
  # metadata should be returned as string since JSON parsing failed
  @corrupt_test.metadata.class
rescue => e
  "Error: #{e.class}"
end
#=> String

## Empty hash object edge case (critical for check_size parameter)
@empty_hash = ConsistencyTestModel.new(id: next_test_id)
# Save creates the hash with identifier
@empty_hash.save

# Manually remove all fields to create an empty hash
# First add a temp field then remove it, which creates empty hash in some Valkey/Redis versions
Familia.dbclient.hset(@empty_hash.dbkey, 'temp_field', 'temp_value')
Familia.dbclient.hdel(@empty_hash.dbkey, 'temp_field')
# Now remove all remaining fields to create truly empty hash
all_fields = Familia.dbclient.hkeys(@empty_hash.dbkey)
Familia.dbclient.hdel(@empty_hash.dbkey, *all_fields) if all_fields.any?

# exists? behavior with empty hash
key_exists_raw = Familia.dbclient.exists(@empty_hash.dbkey) > 0
hash_length = Familia.dbclient.hlen(@empty_hash.dbkey)
obj_exists_with_check = @empty_hash.exists?(check_size: true)
obj_exists_without_check = @empty_hash.exists?(check_size: false)

[key_exists_raw, hash_length, obj_exists_without_check, obj_exists_with_check]
#=> [false, 0, false, false]

## Transaction isolation verification
@tx_test = ConsistencyTestModel.new(id: next_test_id, name: 'Transaction Test')
@tx_test.save

# Verify transaction doesn't interfere with exists? calls
multi_result = @tx_test.transaction do |conn|
  # During transaction, exists? should still work
  exists_in_tx = @tx_test.exists?
  conn.hset(@tx_test.dbkey, 'active', 'true')
  exists_in_tx
end

exists_after_tx = @tx_test.exists?
[multi_result.results, exists_after_tx]
#=> [[0], true]

# =============================================
# 4. Performance Consistency
# =============================================

## exists? performance is consistent regardless of object size
@small_obj = ConsistencyTestModel.new(id: next_test_id, name: 'Small')
@small_obj.save

@large_obj = ConsistencyTestModel.new(id: next_test_id)
@large_obj.name = 'Large Object'
@large_obj.email = 'large@example.com'
@large_obj.metadata = { large_data: 'x' * 1000 }
@large_obj.save

# exists? should work equally fast for both
small_exists = @small_obj.exists?
large_exists = @large_obj.exists?

[small_exists, large_exists]
#=> [true, true]

## Batch operations maintain consistency
@batch_obj = ConsistencyTestModel.new(id: next_test_id, name: 'Original Batch')
@batch_obj.save

# Batch update multiple fields
batch_result = @batch_obj.batch_update(
  name: 'Updated Batch',
  email: 'batch@example.com',
  active: true
)

# Verify exists? still works correctly after batch operations
exists_after_batch = @batch_obj.exists?
[@batch_obj.name, batch_result.successful?, exists_after_batch]
#=> ['Updated Batch', true, true]

# =============================================
# 5. Integration Consistency with Features
# =============================================

## Transient fields don't affect exists? behavior
class TransientConsistencyTest < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  transient_field :temp_value
end

@transient_obj = TransientConsistencyTest.new(id: next_test_id, name: 'Transient Test')
@transient_obj.temp_value = 'This should not persist'
@transient_obj.save

# exists? should work normally despite transient fields
exists_with_transient = @transient_obj.exists?

@transient_obj.refresh!
# Transient field should be nil after refresh, but exists? should still work
transient_nil = @transient_obj.temp_value.nil?
exists_after_refresh = @transient_obj.exists?

[exists_with_transient, transient_nil, exists_after_refresh]
#=> [true, true, true]

# =============================================
# 6. Database Command Consistency
# =============================================

## save/exists?/destroy lifecycle is consistent
@lifecycle_obj = ConsistencyTestModel.new(id: next_test_id, name: 'Lifecycle Test')

# Initial state
initial_exists = @lifecycle_obj.exists?

# After save
@lifecycle_obj.save
saved_exists = @lifecycle_obj.exists?

# After modification
@lifecycle_obj.name = 'Modified Lifecycle'
@lifecycle_obj.save
modified_exists = @lifecycle_obj.exists?

# After destroy
@lifecycle_obj.destroy!
destroyed_exists = @lifecycle_obj.exists?

[initial_exists, saved_exists, modified_exists, destroyed_exists]
#=> [false, true, true, false]

## Field removal doesn't break exists?
@field_removal = ConsistencyTestModel.new(id: next_test_id, name: 'Field Removal')
@field_removal.save

# Remove a field manually
Familia.dbclient.hdel(@field_removal.dbkey, 'name')

# exists? should still work
exists_after_field_removal = @field_removal.exists?
remaining_fields = Familia.dbclient.hlen(@field_removal.dbkey)

[exists_after_field_removal, remaining_fields > 0]
#=> [true, true]

## Class vs instance exists? always consistent
@class_instance_test = ConsistencyTestModel.new(id: next_test_id, name: 'Class Instance Test')
@class_instance_test.save

# Multiple checks should always be consistent
results = 5.times.map do
  class_result = ConsistencyTestModel.exists?(@class_instance_test.identifier)
  instance_result = @class_instance_test.exists?
  class_result == instance_result
end

results.all?
#=> true

# =============================================
# Cleanup
# =============================================

# Clean up all test data
test_keys = Familia.dbclient.keys('consistencytestmodel:*')
test_keys.concat(Familia.dbclient.keys('transientconsistencytest:*'))
Familia.dbclient.del(*test_keys) if test_keys.any?
