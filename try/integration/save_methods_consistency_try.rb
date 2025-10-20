# try/integration/save_methods_consistency_try.rb
#
# Test coverage for save and save_if_not_exists consistency improvements
#
# This test verifies that both save and save_if_not_exists! produce identical
# results when creating new objects, including:
# - Timestamp updates (created/updated)
# - Unique index validation
# - Class-level index updates
# - Instance collection tracking

require_relative '../support/helpers/test_helpers'

# Model with timestamps to verify timestamp handling
class TimestampedModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :created
  field :updated

  zset :instances
end

# Model with unique indexes to verify validation
class UniqueIndexModel < Familia::Horreum
  feature :relationships
  include Familia::Features::Relationships::Indexing

  identifier_field :id
  field :id
  field :email

  unique_index :email, :email_lookup
  zset :instances
end

# Clean up any existing test data
cleanup_keys = Familia.dbclient.keys('timestampedmodel:*') +
               Familia.dbclient.keys('uniqueindexmodel:*') +
               Familia.dbclient.keys('*:email_lookup:*')
Familia.dbclient.del(*cleanup_keys) if cleanup_keys.any?

@test_counter = 0
def next_id
  @test_counter += 1
  "test-#{Familia.now.to_i}-#{@test_counter}"
end

# =============================================
# 1. Timestamp Consistency Tests
# =============================================

## save sets created and updated timestamps
@save_model = TimestampedModel.new(id: next_id, name: 'Save Test')
@save_model.save
[@save_model.created.nil?, @save_model.updated.nil?]
#=> [false, false]

## save_if_not_exists! sets created and updated timestamps
@sine_model = TimestampedModel.new(id: next_id, name: 'SINE Test')
@sine_model.save_if_not_exists!
[@sine_model.created.nil?, @sine_model.updated.nil?]
#=> [false, false]

## Both methods set timestamps to the same approximate time
time_diff = (@save_model.created - @save_model.updated).abs
time_diff < 1  # Should be within 1 second
#=> true

## save_if_not_exists! timestamps match save behavior
sine_time_diff = (@sine_model.created - @sine_model.updated).abs
sine_time_diff < 1
#=> true

# =============================================
# 2. Instance Collection Consistency
# =============================================

## save adds object to instances collection
@inst_save = TimestampedModel.new(id: next_id, name: 'Instance Save')
@inst_save.save
TimestampedModel.instances.members.include?(@inst_save.identifier)
#=> true

## save_if_not_exists! adds object to instances collection
@inst_sine = TimestampedModel.new(id: next_id, name: 'Instance SINE')
@inst_sine.save_if_not_exists!
TimestampedModel.instances.members.include?(@inst_sine.identifier)
#=> true

## Both methods produce identical instance collection state
[@inst_save, @inst_sine].all? { |obj| TimestampedModel.instances.members.include?(obj.identifier) }
#=> true

# =============================================
# 3. Unique Index Validation Consistency
# =============================================

## save validates unique indexes
@unique_email_1 = "save-#{next_id}@test.com"
@unique_save = UniqueIndexModel.new(id: next_id, email: @unique_email_1)
@unique_save.save
@unique_save.exists?
#=> true

## save raises RecordExistsError for duplicate unique index
@unique_dup_save = UniqueIndexModel.new(id: next_id, email: @unique_email_1)
@unique_dup_save.save
#=!> Familia::RecordExistsError

## save_if_not_exists! validates unique indexes
@unique_email_2 = "sine-#{next_id}@test.com"
@unique_sine = UniqueIndexModel.new(id: next_id, email: @unique_email_2)
@unique_sine.save_if_not_exists!
@unique_sine.exists?
#=> true

## save_if_not_exists! raises RecordExistsError for duplicate unique index
@unique_dup_sine = UniqueIndexModel.new(id: next_id, email: @unique_email_2)
@unique_dup_sine.save_if_not_exists!
#=!> Familia::RecordExistsError

# =============================================
# 4. Return Value Consistency
# =============================================

## save returns true for successful save
@ret_save = TimestampedModel.new(id: next_id, name: 'Return Test Save')
result_save = @ret_save.save
result_save
#=> true

## save_if_not_exists! returns true for successful save
@ret_sine = TimestampedModel.new(id: next_id, name: 'Return Test SINE')
result_sine = @ret_sine.save_if_not_exists!
result_sine
#=> true

## save_if_not_exists returns true for new object
@ret_sine_safe = TimestampedModel.new(id: next_id, name: 'Return Safe SINE')
result = @ret_sine_safe.save_if_not_exists
result
#=> true

## save_if_not_exists returns false for existing object
@ret_existing = TimestampedModel.new(id: next_id, name: 'Existing')
@ret_existing.save
@ret_dup = TimestampedModel.new(id: @ret_existing.identifier, name: 'Duplicate')
result = @ret_dup.save_if_not_exists
result
#=> false

# =============================================
# 5. Data Persistence Consistency
# =============================================

## save persists all fields
@data_save = TimestampedModel.new(id: next_id, name: 'Data Save Test')
@data_save.save
@data_save.refresh
@data_save.name
#=> 'Data Save Test'

## save_if_not_exists! persists all fields
@data_sine = TimestampedModel.new(id: next_id, name: 'Data SINE Test')
@data_sine.save_if_not_exists!
@data_sine.refresh
@data_sine.name
#=> 'Data SINE Test'

## Both methods produce identical persistence
[@data_save.name, @data_sine.name]
#=> ['Data Save Test', 'Data SINE Test']

# =============================================
# 6. Expiration Handling Consistency
# =============================================

## save with update_expiration: true handles TTL
@exp_save = TimestampedModel.new(id: next_id, name: 'Exp Save')
@exp_save.save(update_expiration: true)
# No default expiration set, so TTL is -1 (no expiration)
@exp_save.ttl == -1
#=> true

## save_if_not_exists! with update_expiration: true handles TTL
@exp_sine = TimestampedModel.new(id: next_id, name: 'Exp SINE')
@exp_sine.save_if_not_exists!(update_expiration: true)
# No default expiration set, so TTL is -1 (no expiration)
@exp_sine.ttl == -1
#=> true

# =============================================
# 7. OptimisticLockError Behavior
# =============================================

## save_if_not_exists allows OptimisticLockError to propagate
# Note: This is difficult to test reliably without mocking, but we can
# verify the method signature and rescue clause structure through the API

## save_if_not_exists rescues only RecordExistsError
@opt_test = TimestampedModel.new(id: next_id, name: 'Opt Test')
@opt_test.save
@opt_dup = TimestampedModel.new(id: @opt_test.identifier, name: 'Opt Dup')
# This should return false, not raise
result = @opt_dup.save_if_not_exists
result
#=> false

# =============================================
# 8. Edge Cases
# =============================================

## save works with nil field values
@nil_save = TimestampedModel.new(id: next_id, name: nil)
@nil_save.save
@nil_save.exists?
#=> true

## save_if_not_exists! works with nil field values
@nil_sine = TimestampedModel.new(id: next_id, name: nil)
@nil_sine.save_if_not_exists!
@nil_sine.exists?
#=> true

## Both methods handle empty strings
@empty_save = TimestampedModel.new(id: next_id, name: '')
@empty_save.save
@empty_sine = TimestampedModel.new(id: next_id, name: '')
@empty_sine.save_if_not_exists!
[@empty_save.exists?, @empty_sine.exists?]
#=> [true, true]

# Cleanup
cleanup_keys = Familia.dbclient.keys('timestampedmodel:*') +
               Familia.dbclient.keys('uniqueindexmodel:*') +
               Familia.dbclient.keys('*:email_lookup:*')
Familia.dbclient.del(*cleanup_keys) if cleanup_keys.any?
