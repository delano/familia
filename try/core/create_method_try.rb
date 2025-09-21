# try/core/create_method_try.rb
#
# Comprehensive test coverage for the create method
# Tests the correct exception type and error message handling

require_relative '../helpers/test_helpers'

# Test class for create method behavior
class CreateTestModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :value
end

# Clean up any existing test data
cleanup_keys = []
begin
  existing_test_keys = Familia.dbclient.keys('create_test_model:*')
  cleanup_keys.concat(existing_test_keys)
  Familia.dbclient.del(*existing_test_keys) if existing_test_keys.any?
rescue => e
  # Ignore cleanup errors
end

@test_id_counter = 0
def next_test_id
  @test_id_counter += 1
  identifier = "create-test-#{Familia.now.to_i}-#{@test_id_counter}"
  identifier
end

@first_test_id = next_test_id

# =============================================
# 1. Basic create method functionality
# =============================================

## create method successfully creates new object
@created_obj = CreateTestModel.create(id: @first_test_id, name: 'Created Object', value: 'test_value')
[@created_obj.class, @created_obj.exists?, @created_obj.name]
#=> [CreateTestModel, true, 'Created Object']

## create method returns the created object
@created_obj.is_a?(CreateTestModel)
#=> true

## create method persists object fields
@created_obj.refresh!
[@created_obj.name, @created_obj.value]
#=> ['Created Object', 'test_value']

# =============================================
# 2. Duplicate creation error handling
# =============================================

## create method raises RecordExistsError for duplicate
CreateTestModel.create(id: @first_test_id, name: 'Duplicate Attempt')
#=!> Familia::RecordExistsError

## RecordExistsError includes the dbkey in the message
CreateTestModel.create(id: @first_test_id, name: 'Another Duplicate')
#=!> Familia::RecordExistsError
#==> !!error.message.match(/create_test_model:#{@first_test_id}:object/)

## RecordExistsError message follows consistent format
begin
  CreateTestModel.create(id: @first_test_id, name: 'Yet Another Duplicate')
  false  # Should not reach here
rescue Familia::RecordExistsError => e
  e.message.start_with?('Key already exists:')
end
#=> true

## RecordExistsError exposes key property for programmatic access
@final_test_id = next_test_id
CreateTestModel.create(id: @final_test_id, name: 'Setup for Key Test')

begin
  CreateTestModel.create(id: @final_test_id, name: 'Key Test Duplicate')
  false  # Should not reach here
rescue Familia::RecordExistsError => e
  # Key should be accessible and contain the identifier
  [e.respond_to?(:key), e.key.include?(@final_test_id)]
end
#=> [true, true]

# =============================================
# 3. Edge cases and error conditions
# =============================================

## create with empty identifier raises NoIdentifier error
CreateTestModel.create(id: '')
#=!> Familia::NoIdentifier

## create with nil identifier raises NoIdentifier error
CreateTestModel.create(id: nil)
#=!> Familia::NoIdentifier

## create with only some fields set
@partial_id = next_test_id
@partial_obj = CreateTestModel.create(id: @partial_id, name: 'Partial Object')
[@partial_obj.exists?, @partial_obj.name, @partial_obj.value]
#=> [true, 'Partial Object', nil]

## create with no additional fields (only identifier)
@minimal_id = next_test_id
@minimal_obj = CreateTestModel.create(id: @minimal_id)
[@minimal_obj.exists?, @minimal_obj.id]
#=> [true, @minimal_id]

# =============================================
# 4. Concurrency and transaction behavior
# =============================================

## create is atomic - no partial state on failure
@concurrent_id = next_test_id
@first_obj = CreateTestModel.create(id: @concurrent_id, name: 'First')

# Verify first object exists
first_exists = @first_obj.exists?

# Attempt to create duplicate should not affect existing object
begin
  CreateTestModel.create(id: @concurrent_id, name: 'Concurrent Attempt')
  false  # Should not reach here
rescue Familia::RecordExistsError
  # Original object should be unchanged
  @first_obj.refresh!
  @first_obj.name == 'First'
end
#=> true

## create failure doesn't leave partial data
before_failed_create = Familia.dbclient.keys("create_test_model:#{@concurrent_id}:*").length
begin
  CreateTestModel.create(id: @concurrent_id, name: 'Should Fail')
rescue Familia::RecordExistsError
  # Should not create any additional keys
  after_failed_create = Familia.dbclient.keys("create_test_model:#{@concurrent_id}:*").length
  after_failed_create == before_failed_create
end
#=> true

# =============================================
# 5. Consistency with save_if_not_exists
# =============================================

## Both create and save_if_not_exists raise same error type for duplicates
@consistency_id = next_test_id
@consistency_obj = CreateTestModel.create(id: @consistency_id, name: 'Consistency Test')

# Test create raises RecordExistsError
create_error_class = begin
  CreateTestModel.create(id: @consistency_id, name: 'Create Duplicate')
  nil
rescue => e
  e.class
end

# Test save_if_not_exists raises RecordExistsError
sine_error_class = begin
  duplicate_obj = CreateTestModel.new(id: @consistency_id, name: 'SINE Duplicate')
  duplicate_obj.save_if_not_exists
  nil
rescue => e
  e.class
end

[create_error_class, sine_error_class]
#=> [Familia::RecordExistsError, Familia::RecordExistsError]

## Both methods have similar error message patterns
@error_comparison_id = next_test_id
CreateTestModel.create(id: @error_comparison_id, name: 'Error Comparison')

create_error_msg = begin
  CreateTestModel.create(id: @error_comparison_id, name: 'Create Error')
  nil
rescue => e
  e.message
end

sine_error_msg = begin
  CreateTestModel.new(id: @error_comparison_id, name: 'SINE Error').save_if_not_exists
  nil
rescue => e
  e.message
end

# Both should reference the same key concept
[create_error_msg.include?('already exists'), sine_error_msg.include?('already exists')]
#=> [true, true]

# =============================================
# 6. Integration with different field types
# =============================================

## create works with complex field values
@complex_id = next_test_id
@complex_obj = CreateTestModel.create(
  id: @complex_id,
  name: 'Complex Object',
  value: { nested: 'data', array: [1, 2, 3] }
)
[@complex_obj.exists?, @complex_obj.value[:nested]]
#=> [true, 'data']

# =============================================
# 7. Class vs instance method consistency
# =============================================

## Class.create and instance.save_if_not_exists have consistent existence checking
@consistency_check_id = next_test_id

# Create via class method
@class_created = CreateTestModel.create(id: @consistency_check_id, name: 'Class Created')

# Both class and instance methods should see the object as existing
class_sees_exists = CreateTestModel.exists?(@consistency_check_id)
instance_sees_exists = @class_created.exists?

[class_sees_exists, instance_sees_exists]
#=> [true, true]

# =============================================
# Cleanup
# =============================================

# Clean up all test data
test_keys = Familia.dbclient.keys('create_test_model:*')
Familia.dbclient.del(*test_keys) if test_keys.any?
