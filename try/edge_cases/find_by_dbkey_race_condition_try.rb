# try/edge_cases/find_by_dbkey_race_condition_try.rb
#
# frozen_string_literal: true

# Test race condition handling in find_by_dbkey where a key can expire
# between the EXISTS check and HGETALL retrieval. Also tests lazy cleanup
# of stale instances entries.
#
# The race condition scenario:
# 1. EXISTS check passes (key exists)
# 2. Key expires via TTL (or is deleted) before HGETALL
# 3. HGETALL returns empty hash {}
# 4. Without fix: instantiate_from_hash({}) creates object with nil identifier
# 5. With fix: returns nil and cleans up stale instances entry

require_relative '../support/helpers/test_helpers'

RaceConditionUser = Class.new(Familia::Horreum) do
  identifier_field :user_id
  field :user_id
  field :name
  field :email
end

RaceConditionSession = Class.new(Familia::Horreum) do
  identifier_field :session_id
  field :session_id
  field :data
  feature :expiration
  default_expiration 300
end

# --- Empty Hash Handling Tests ---

## find_by_dbkey returns nil for empty hash when check_exists: true
# Simulate race condition: add stale entry to instances, then try to load
RaceConditionUser.instances.add('stale_user_1', Familia.now)
initial_count = RaceConditionUser.instances.size
result = RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('stale_user_1'), check_exists: true)
result
#=> nil

## find_by_dbkey returns nil for empty hash when check_exists: false
RaceConditionUser.instances.add('stale_user_2', Familia.now)
result = RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('stale_user_2'), check_exists: false)
result
#=> nil

## find_by_dbkey handles both check_exists modes consistently for non-existent keys
result_true = RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('nonexistent_1'), check_exists: true)
result_false = RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('nonexistent_2'), check_exists: false)
[result_true, result_false]
#=> [nil, nil]

# --- Lazy Cleanup Tests ---

## lazy cleanup removes stale entry from instances when loading fails
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('phantom_user_1', Familia.now)
before_count = RaceConditionUser.instances.size
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_user_1'))
after_count = RaceConditionUser.instances.size
[before_count, after_count]
#=> [1, 0]

## lazy cleanup handles multiple stale entries
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('phantom_a', Familia.now)
RaceConditionUser.instances.add('phantom_b', Familia.now)
RaceConditionUser.instances.add('phantom_c', Familia.now)
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_a'))
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_b'))
remaining = RaceConditionUser.instances.size
remaining
#=> 1

## lazy cleanup only removes the specific stale entry
RaceConditionUser.instances.clear
real_user = RaceConditionUser.new(user_id: 'real_user_1', name: 'Real', email: 'real@example.com')
real_user.save
RaceConditionUser.instances.add('phantom_mixed', Familia.now)
before = RaceConditionUser.instances.members.sort
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_mixed'))
after = RaceConditionUser.instances.members.sort
real_user.destroy!
[before.include?('phantom_mixed'), before.include?('real_user_1'), after.include?('phantom_mixed'), after.include?('real_user_1')]
#=> [true, true, false, true]

# --- Race Condition Simulation Tests ---

## simulated race: key deleted between conceptual EXISTS and actual load
# This simulates what happens when a key expires between EXISTS and HGETALL
user = RaceConditionUser.new(user_id: 'race_user_1', name: 'Race', email: 'race@example.com')
user.save
dbkey = RaceConditionUser.dbkey('race_user_1')

# Verify key exists
exists_before = Familia.dbclient.exists(dbkey).positive?

# Simulate TTL expiration by directly deleting the key but leaving instances entry
Familia.dbclient.del(dbkey)

# Now find_by_dbkey should return nil and clean up instances
result = RaceConditionUser.find_by_dbkey(dbkey)
exists_after = RaceConditionUser.instances.members.include?('race_user_1')
[exists_before, result, exists_after]
#=> [true, nil, false]

## simulated race with check_exists: false also handles cleanup
user2 = RaceConditionUser.new(user_id: 'race_user_2', name: 'Race2', email: 'race2@example.com')
user2.save
dbkey2 = RaceConditionUser.dbkey('race_user_2')

# Delete key but leave instances entry
Familia.dbclient.del(dbkey2)

result = RaceConditionUser.find_by_dbkey(dbkey2, check_exists: false)
cleaned = !RaceConditionUser.instances.members.include?('race_user_2')
[result, cleaned]
#=> [nil, true]

# --- TTL Expiration Tests ---

## TTL expiration leaves stale instances entry (demonstrating the problem)
session = RaceConditionSession.new(session_id: 'ttl_session_1', data: 'test data')
session.save
session.expire(1) # 1 second TTL

# Verify it's in instances
in_instances_before = RaceConditionSession.instances.members.include?('ttl_session_1')

# Wait for TTL to expire
sleep(1.5)

# Key is gone but instances entry remains (this is the stale entry problem)
key_exists = Familia.dbclient.exists(RaceConditionSession.dbkey('ttl_session_1')).positive?
in_instances_still = RaceConditionSession.instances.members.include?('ttl_session_1')
[in_instances_before, key_exists, in_instances_still]
#=> [true, false, true]

## lazy cleanup fixes stale entry after TTL expiration
# Now when we try to load, it should clean up the stale entry
result = RaceConditionSession.find_by_dbkey(RaceConditionSession.dbkey('ttl_session_1'))
in_instances_after = RaceConditionSession.instances.members.include?('ttl_session_1')
[result, in_instances_after]
#=> [nil, false]

## find methods clean up stale entries after TTL expiration
session2 = RaceConditionSession.new(session_id: 'ttl_session_2', data: 'test data 2')
session2.save
session2.expire(1)
sleep(1.5)

# Use find_by_id (which calls find_by_dbkey internally)
result = RaceConditionSession.find_by_id('ttl_session_2')
cleaned = !RaceConditionSession.instances.members.include?('ttl_session_2')
[result, cleaned]
#=> [nil, true]

# --- Count Consistency Tests ---

## count reflects reality after lazy cleanup
RaceConditionUser.instances.clear
# Create real user
real = RaceConditionUser.new(user_id: 'count_real', name: 'Real', email: 'real@example.com')
real.save

# Add phantom entries
RaceConditionUser.instances.add('count_phantom_1', Familia.now)
RaceConditionUser.instances.add('count_phantom_2', Familia.now)

count_before = RaceConditionUser.count

# Trigger lazy cleanup by attempting to load phantoms
RaceConditionUser.find_by_id('count_phantom_1')
RaceConditionUser.find_by_id('count_phantom_2')

count_after = RaceConditionUser.count
real.destroy!
[count_before, count_after]
#=> [3, 1]

## keys_count vs count after lazy cleanup
RaceConditionUser.instances.clear
real2 = RaceConditionUser.new(user_id: 'keys_count_real', name: 'Real', email: 'real@example.com')
real2.save
RaceConditionUser.instances.add('keys_count_phantom', Familia.now)

# Before cleanup: count includes phantom, keys_count doesn't
count_before = RaceConditionUser.count
keys_count_before = RaceConditionUser.keys_count

# Trigger lazy cleanup
RaceConditionUser.find_by_id('keys_count_phantom')

# After cleanup: both should match
count_after = RaceConditionUser.count
keys_count_after = RaceConditionUser.keys_count

real2.destroy!
[count_before, keys_count_before, count_after, keys_count_after]
#=> [2, 1, 1, 1]

# --- Edge Cases ---

## empty identifier in key doesn't cause issues
# Key format with empty identifier would be "prefix::suffix"
# This shouldn't happen in practice, but we handle it gracefully
malformed_key = "#{RaceConditionUser.prefix}::object"
result = RaceConditionUser.find_by_dbkey(malformed_key)
result
#=> nil

## key with unusual identifier characters
RaceConditionUser.instances.add('user:with:colons', Familia.now)
result = RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('user:with:colons'))
# Should return nil (key doesn't exist) and attempt cleanup
# Note: cleanup may not work perfectly for identifiers with delimiters
result
#=> nil

## concurrent load attempts on same stale entry
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('concurrent_phantom', Familia.now)

threads = []
results = []
mutex = Mutex.new

5.times do
  threads << Thread.new do
    r = RaceConditionUser.find_by_id('concurrent_phantom')
    mutex.synchronize { results << r }
  end
end

threads.each(&:join)

# All should return nil, and instances should be cleaned
all_nil = results.all?(&:nil?)
cleaned = !RaceConditionUser.instances.members.include?('concurrent_phantom')
[all_nil, cleaned, results.size]
#=> [true, true, 5]

# --- Cleanup ---

RaceConditionUser.instances.clear
RaceConditionSession.instances.clear
