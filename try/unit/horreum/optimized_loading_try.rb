# try/unit/horreum/optimized_loading_try.rb
#
# frozen_string_literal: true

# Test optimized loading methods with check_exists parameter and pipelined bulk loading

require_relative '../../support/helpers/test_helpers'

OptimizedUser = Class.new(Familia::Horreum) do
  identifier_field :user_id
  field :user_id
  field :name
  field :email
  field :age
end

# Setup: Create test users
setup_user1 = OptimizedUser.new(user_id: 'opt_user_1', name: 'Alice', email: 'alice@example.com', age: 30)
setup_user1.save

setup_user2 = OptimizedUser.new(user_id: 'opt_user_2', name: 'Bob', email: 'bob@example.com', age: 25)
setup_user2.save

setup_user3 = OptimizedUser.new(user_id: 'opt_user_3', name: 'Charlie', email: 'charlie@example.com', age: 35)
setup_user3.save

## find_by_dbkey with check_exists: true (default) returns object for existing key
found_user = OptimizedUser.find_by_dbkey(OptimizedUser.dbkey('opt_user_1'))
found_user.name
#=> 'Alice'

## find_by_dbkey with check_exists: true (default) returns nil for non-existent key
OptimizedUser.find_by_dbkey(OptimizedUser.dbkey('nonexistent'))
#=> nil

## find_by_dbkey with check_exists: false returns object for existing key
found_user_fast = OptimizedUser.find_by_dbkey(OptimizedUser.dbkey('opt_user_1'), check_exists: false)
found_user_fast.name
#=> 'Alice'

## find_by_dbkey with check_exists: false returns nil for non-existent key
OptimizedUser.find_by_dbkey(OptimizedUser.dbkey('nonexistent'), check_exists: false)
#=> nil

## find_by_dbkey with check_exists: false correctly deserializes all fields
fast_loaded = OptimizedUser.find_by_dbkey(OptimizedUser.dbkey('opt_user_2'), check_exists: false)
[fast_loaded.user_id, fast_loaded.name, fast_loaded.email, fast_loaded.age]
#=> ['opt_user_2', 'Bob', 'bob@example.com', 25]

## find_by_identifier with check_exists: true (default) returns object
OptimizedUser.find_by_identifier('opt_user_1').name
#=> 'Alice'

## find_by_identifier with check_exists: false returns object
OptimizedUser.find_by_identifier('opt_user_1', check_exists: false).name
#=> 'Alice'

## find_by_identifier with check_exists: false returns nil for non-existent
OptimizedUser.find_by_identifier('nonexistent', check_exists: false)
#=> nil

## find_by_id alias works with check_exists parameter
OptimizedUser.find_by_id('opt_user_2', check_exists: false).email
#=> 'bob@example.com'

## find alias works with check_exists parameter
OptimizedUser.find('opt_user_3', check_exists: false).age
#=> 35

## load alias works with check_exists parameter
OptimizedUser.load('opt_user_1', check_exists: false).user_id
#=> 'opt_user_1'

## load_multi loads multiple existing objects
users = OptimizedUser.load_multi(['opt_user_1', 'opt_user_2', 'opt_user_3'])
users.map(&:name)
#=> ['Alice', 'Bob', 'Charlie']

## load_multi returns nils for non-existent objects in correct positions
users_mixed = OptimizedUser.load_multi(['opt_user_1', 'nonexistent', 'opt_user_3'])
[users_mixed[0]&.name, users_mixed[1], users_mixed[2]&.name]
#=> ['Alice', nil, 'Charlie']

## load_multi with compact filters out nils
users_compact = OptimizedUser.load_multi(['opt_user_1', 'nonexistent', 'opt_user_2']).compact
users_compact.map(&:name)
#=> ['Alice', 'Bob']

## load_multi preserves order of identifiers
users_ordered = OptimizedUser.load_multi(['opt_user_3', 'opt_user_1', 'opt_user_2'])
users_ordered.map(&:user_id)
#=> ['opt_user_3', 'opt_user_1', 'opt_user_2']

## load_multi handles empty array
OptimizedUser.load_multi([])
#=> []

## load_multi handles all non-existent identifiers
all_missing = OptimizedUser.load_multi(['missing1', 'missing2'])
all_missing.compact
#=> []

## load_multi correctly deserializes all field types
multi_loaded = OptimizedUser.load_multi(['opt_user_2']).first
[multi_loaded.user_id, multi_loaded.name, multi_loaded.email, multi_loaded.age]
#=> ['opt_user_2', 'Bob', 'bob@example.com', 25]

## load_batch alias works
batch_users = OptimizedUser.load_batch(['opt_user_1', 'opt_user_2'])
batch_users.map(&:name)
#=> ['Alice', 'Bob']

## load_multi_by_keys loads by full dbkeys
keys = [OptimizedUser.dbkey('opt_user_1'), OptimizedUser.dbkey('opt_user_2')]
keyed_users = OptimizedUser.load_multi_by_keys(keys)
keyed_users.map(&:name)
#=> ['Alice', 'Bob']

## load_multi_by_keys returns nil for non-existent keys
keys_mixed = [OptimizedUser.dbkey('opt_user_1'), OptimizedUser.dbkey('nonexistent')]
keyed_mixed = OptimizedUser.load_multi_by_keys(keys_mixed)
[keyed_mixed[0]&.name, keyed_mixed[1]]
#=> ['Alice', nil]

## load_multi_by_keys handles empty array
OptimizedUser.load_multi_by_keys([])
#=> []

## load_multi_by_keys handles empty/nil keys and maintains position alignment
keys_with_empty = [OptimizedUser.dbkey('opt_user_1'), '', OptimizedUser.dbkey('opt_user_2'), nil]
mixed_keys = OptimizedUser.load_multi_by_keys(keys_with_empty)
[mixed_keys[0]&.name, mixed_keys[1], mixed_keys[2]&.name, mixed_keys[3]]
#=> ['Alice', nil, 'Bob', nil]

## load_multi handles nil identifiers gracefully
users_with_nils = OptimizedUser.load_multi(['opt_user_1', nil, 'opt_user_2'])
[users_with_nils[0]&.name, users_with_nils[1], users_with_nils[2]&.name]
#=> ['Alice', nil, 'Bob']

## load_multi handles empty string identifiers
users_with_empty = OptimizedUser.load_multi(['opt_user_1', '', 'opt_user_2'])
[users_with_empty[0]&.name, users_with_empty[1], users_with_empty[2]&.name]
#=> ['Alice', nil, 'Bob']

## find_by_identifier works with suffix as keyword parameter
OptimizedUser.find_by_identifier('opt_user_1', suffix: :object)&.name
#=> 'Alice'

## find_by_identifier works with both keyword parameters
OptimizedUser.find_by_identifier('opt_user_1', suffix: :object, check_exists: false)&.name
#=> 'Alice'

# Teardown: Clean up test data
OptimizedUser.destroy!('opt_user_1')
OptimizedUser.destroy!('opt_user_2')
OptimizedUser.destroy!('opt_user_3')
