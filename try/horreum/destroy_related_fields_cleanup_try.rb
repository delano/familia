# Horreum destroy! Related Fields Cleanup Tryouts
#
# Tests that when a Horreum instance is destroyed, all its related fields
# (lists, sets, sorted sets, hashes, etc.) are also properly cleaned up
# to prevent orphaned Redis keys.
#
# This addresses the bug where destroy! only deleted the main object key
# but left related field keys in the database.

require_relative '../helpers/test_helpers'

MANY_FIELD_MULTIPLIER = 10

# Test model with various related fields
class ::DestroyTestUser < Familia::Horreum
  identifier_field :user_id
  field :user_id
  field :name
  field :email

  # Various DataType relations to test cleanup
  list :activity_log
  set :tags
  zset :scores
  hashkey :settings
  string :status_message
end

class ::CustomOptionsUser < Familia::Horreum
  identifier_field :user_id
  field :user_id

  # Related fields with various options
  list :custom_log, ttl: 3600
  set :custom_tags, default: ['default_tag']
  zset :custom_scores, class: self
end

class ::ParentModel < Familia::Horreum
  identifier_field :parent_id
  field :parent_id
  list :children_ids
  set :child_tags
end

class ::ChildModel < Familia::Horreum
  identifier_field :child_id
  field :child_id
  field :parent_id
  list :child_activities
end

class ::ManyFieldsModel < Familia::Horreum
  identifier_field :model_id
  field :model_id

  # Create many different types of related fields
  MANY_FIELD_MULTIPLIER.times do |i|
    list :"list_#{i}"
    set :"set_#{i}"
    zset :"zset_#{i}"
    hashkey :"hash_#{i}"
  end
end

# From transaction_fallback_integration_try.rb for bug verification test
class ::IntegrationTestUser < Familia::Horreum
  identifier_field :user_id
  field :user_id
  field :name
  field :email
  field :status
  list :activity_log
  set :tags
  zset :scores
end

## Related fields are cleaned up when instance is destroyed
user = DestroyTestUser.new(user_id: 'cleanup_test_001', name: 'Test User')

# Populate related fields with data
user.activity_log.add('login')
user.activity_log.add('profile_update')

user.tags.add('premium')
user.tags.add('verified')

user.scores.add('game_score', 100)
user.scores.add('quiz_score', 85)

user.settings['theme'] = 'dark'
user.settings['notifications'] = 'enabled'

user.status_message.value = 'Online'

user.save

# Verify data exists before destruction
keys_before = [
  user.dbkey,
  user.activity_log.dbkey,
  user.tags.dbkey,
  user.scores.dbkey,
  user.settings.dbkey,
  user.status_message.dbkey,
]

keys_exist_before = keys_before.all? { |key| user.dbclient.exists(key) > 0 }

# Destroy the user
destroy_result = user.destroy!

# Verify all keys are cleaned up after destruction
keys_exist_after = keys_before.any? { |key| user.dbclient.exists(key) > 0 }

# Should successfully destroy and clean up all related keys
destroy_result && keys_exist_before && !keys_exist_after
#=> true

## Class-level destroy! also cleans up related fields

user = DestroyTestUser.new(user_id: 'class_destroy_test_001')

# Add some related field data
user.activity_log.add('created')
user.tags.add('new_user')
user.scores.add('initial_score', 0)
user.save

# Verify keys exist
keys_before = [
  user.dbkey,
  user.activity_log.dbkey,
  user.tags.dbkey,
  user.scores.dbkey,
]
keys_exist_before = keys_before.all? { |key| user.dbclient.exists(key) > 0 }

# Use class-level destroy!
destroy_result = DestroyTestUser.destroy!('class_destroy_test_001')

# Verify all keys are cleaned up
keys_exist_after = keys_before.any? { |key| user.dbclient.exists(key) > 0 }

destroy_result && keys_exist_before && !keys_exist_after
#=> true

## Empty related fields don't cause errors during cleanup
user = DestroyTestUser.new(user_id: 'empty_fields_test_001')
user.save

# Don't add any data to related fields - they should be empty

# Destroy should work without errors even with empty related fields
result = user.destroy!

# Verify main key is gone
main_key_gone = user.dbclient.exists(user.dbkey) == 0

result && main_key_gone
#=> true

## Related fields with custom options are handled properly
user = CustomOptionsUser.new(user_id: 'custom_options_test_001')

# Add data to custom related fields
user.custom_log.add('custom_event')
user.custom_tags.add('custom_tag')
user.custom_scores.add('custom_score', 50)
user.save

# Verify keys exist
keys_before = [
  user.dbkey,
  user.custom_log.dbkey,
  user.custom_tags.dbkey,
  user.custom_scores.dbkey,
]
keys_exist_before = keys_before.all? { |key| user.dbclient.exists(key) > 0 }

# Destroy and verify cleanup
destroy_result = user.destroy!
keys_exist_after = keys_before.any? { |key| user.dbclient.exists(key) > 0 }

# Clean up the test class to avoid pollution
Object.send(:remove_const, :CustomOptionsUser) if Object.const_defined?(:CustomOptionsUser)

destroy_result && keys_exist_before && !keys_exist_after
#=> true

## Nested destruction handles complex related field hierarchies

parent = ParentModel.new(parent_id: 'parent_001')
child1 = ChildModel.new(child_id: 'child_001', parent_id: 'parent_001')
child2 = ChildModel.new(child_id: 'child_002', parent_id: 'parent_001')

# Set up relationships
parent.children_ids.add('child_001')
parent.children_ids.add('child_002')
parent.child_tags.add('family_tag')

child1.child_activities.add('child1_activity')
child2.child_activities.add('child2_activity')

parent.save
child1.save
child2.save

# Verify all keys exist
all_keys = [
  parent.dbkey, parent.children_ids.dbkey, parent.child_tags.dbkey,
  child1.dbkey, child1.child_activities.dbkey,
  child2.dbkey, child2.child_activities.dbkey
]
keys_exist_before = all_keys.all? { |key| parent.dbclient.exists(key) > 0 }

# Destroy parent - should clean up all parent's related fields
parent_destroy_result = parent.destroy!

# Parent and its related fields should be gone
parent_keys = [parent.dbkey, parent.children_ids.dbkey, parent.child_tags.dbkey]
parent_keys_gone = parent_keys.none? { |key| parent.dbclient.exists(key) > 0 }

# Child objects should still exist (they're separate objects)
child_keys = [child1.dbkey, child1.child_activities.dbkey, child2.dbkey, child2.child_activities.dbkey]
child_keys_exist = child_keys.all? { |key| child1.dbclient.exists(key) > 0 }

# Clean up children
child1.destroy!
child2.destroy!

# Clean up test classes
Object.send(:remove_const, :ParentModel) if Object.const_defined?(:ParentModel)
Object.send(:remove_const, :ChildModel) if Object.const_defined?(:ChildModel)

parent_destroy_result && keys_exist_before && parent_keys_gone && child_keys_exist
#=> true

## Performance check - destroying object with many related fields
model = ManyFieldsModel.new(model_id: 'many_fields_001')

# Add data to some of the fields
MANY_FIELD_MULTIPLIER.times do |i|
  model.send(:"list_#{i}").add("item_#{i}")
  model.send(:"set_#{i}").add("tag_#{i}")
  model.send(:"zset_#{i}").add("score_#{i}", i * 10)
  model.send(:"hash_#{i}")["key_#{i}"] = "value_#{i}"
end

model.save

destroy_result = model.destroy!

# Should result in success and also complete in a reasonable amount of
# time (under 100ms for this test). I acknowledge this is flaky.
[destroy_result.class, destroy_result.successful?, destroy_result.results.size]
#=> [MultiResult, true, 41]
#=%> 100

## Verify transaction_fallback_integration_try.rb bug is fixed
# Recreate the scenario from the failing test
user = IntegrationTestUser.new(user_id: 'bugfix_test_001')

# Add data to related fields like the original test
user.activity_log.add('user_created')
user.activity_log.add('profile_updated')
user.tags.add('premium')
user.tags.add('verified')
user.scores.add('game_score', 100)
user.scores.add('quiz_score', 85)

# Save the user so the main object key exists
user.save

# Verify keys exist before destruction
keys_before = [
  user.dbkey,
  user.activity_log.dbkey,
  user.tags.dbkey,
  user.scores.dbkey,
]
keys_exist_before = keys_before.all? { |key| user.dbclient.exists(key) > 0 }

# The original destroy! call that was leaving orphaned keys
destroy_result = user.destroy!

# Now all related keys should be properly cleaned up
keys_exist_after = keys_before.any? { |key| user.dbclient.exists(key) > 0 }

Object.send(:remove_const, :ManyFieldsModel) if Object.const_defined?(:ManyFieldsModel)

destroy_result && keys_exist_before && !keys_exist_after
#=> true

## Test destroy! with init hook that depends on identifier
# This verifies that the temp instance initialization fix works correctly
class TestModelWithInit < Familia::Horreum
  identifier_field :user_id
  field :user_id
  field :region
  list :activities

  def init(*args, **kwargs)
    # Set region based on user_id (simulates real-world logic)
    self.region = user_id.split('-').first if user_id
  end
end

# Create object - init should set region based on user_id
init_obj = TestModelWithInit.new(user_id: "us-west-123")
init_obj.save
init_obj.activities << "login"
init_obj.activities << "purchase"

# Verify init worked and region is set
region_set_correctly = init_obj.region == "us"

# Verify related field key includes region (would be nil without fix)
activities_key = init_obj.activities.dbkey

# Destroy using class method - temp instance init should execute with identifier
TestModelWithInit.destroy!("us-west-123")

# Verify all keys are cleaned up (including activities with correct key)
activities_cleaned = TestModelWithInit.dbclient.exists(activities_key).zero?

Object.send(:remove_const, :TestModelWithInit) if Object.const_defined?(:TestModelWithInit)

region_set_correctly && activities_cleaned
#=> true
