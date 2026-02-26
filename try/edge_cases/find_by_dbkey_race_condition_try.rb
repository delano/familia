# try/edge_cases/find_by_dbkey_race_condition_try.rb
#
# frozen_string_literal: true

# Test race condition handling in find_by_dbkey where a key can expire
# between the EXISTS check and HGETALL retrieval.
#
# find_by_dbkey is read-only: it never mutates instances or other state.
# Ghost cleanup is the caller's responsibility via cleanup_stale_instance_entry.
#
# The race condition scenario:
# 1. EXISTS check passes (key exists)
# 2. Key expires via TTL (or is deleted) before HGETALL
# 3. HGETALL returns empty hash {}
# 4. Without fix: instantiate_from_hash({}) creates object with nil identifier
# 5. With fix: returns nil (no side effects)

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
RaceConditionUser.instances.add('stale_user_1', Familia.now)
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

# --- Read-Only Guarantee Tests ---

## find_by_dbkey does NOT remove stale entries from instances
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('phantom_user_1', Familia.now)
before_count = RaceConditionUser.instances.size
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_user_1'))
after_count = RaceConditionUser.instances.size
[before_count, after_count]
#=> [1, 1]

## find_by_dbkey leaves all phantom entries intact
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('phantom_a', Familia.now)
RaceConditionUser.instances.add('phantom_b', Familia.now)
RaceConditionUser.instances.add('phantom_c', Familia.now)
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_a'))
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_b'))
remaining = RaceConditionUser.instances.size
remaining
#=> 3

## find_by_dbkey does not affect any instances entries
RaceConditionUser.instances.clear
real_user = RaceConditionUser.new(user_id: 'real_user_1', name: 'Real', email: 'real@example.com')
real_user.save
RaceConditionUser.instances.add('phantom_mixed', Familia.now)
before = RaceConditionUser.instances.members.sort
RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('phantom_mixed'))
after = RaceConditionUser.instances.members.sort
real_user.destroy!
[before.include?('phantom_mixed'), before.include?('real_user_1'), after.include?('phantom_mixed'), after.include?('real_user_1')]
#=> [true, true, true, true]

# --- Explicit Cleanup Tests ---

## cleanup_stale_instance_entry removes a phantom entry
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('cleanup_target', Familia.now)
RaceConditionUser.cleanup_stale_instance_entry(RaceConditionUser.dbkey('cleanup_target'))
RaceConditionUser.instances.members.include?('cleanup_target')
#=> false

## cleanup_stale_instance_entry only removes the specific entry
RaceConditionUser.instances.clear
RaceConditionUser.instances.add('keep_this', Familia.now)
RaceConditionUser.instances.add('remove_this', Familia.now)
RaceConditionUser.cleanup_stale_instance_entry(RaceConditionUser.dbkey('remove_this'))
[RaceConditionUser.instances.members.include?('keep_this'), RaceConditionUser.instances.members.include?('remove_this')]
#=> [true, false]

# --- Race Condition Simulation Tests ---

## simulated race: key deleted between conceptual EXISTS and actual load
@race_user = RaceConditionUser.new(user_id: 'race_user_1', name: 'Race', email: 'race@example.com')
@race_user.save
@race_dbkey = RaceConditionUser.dbkey('race_user_1')
exists_before = Familia.dbclient.exists(@race_dbkey).positive?
Familia.dbclient.del(@race_dbkey)
result = RaceConditionUser.find_by_dbkey(@race_dbkey)
in_instances = RaceConditionUser.instances.members.include?('race_user_1')
[exists_before, result, in_instances]
#=> [true, nil, true]

## explicit cleanup after detecting stale entry
RaceConditionUser.cleanup_stale_instance_entry(@race_dbkey)
RaceConditionUser.instances.members.include?('race_user_1')
#=> false

## simulated race with check_exists: false returns nil without cleanup
user2 = RaceConditionUser.new(user_id: 'race_user_2', name: 'Race2', email: 'race2@example.com')
user2.save
dbkey2 = RaceConditionUser.dbkey('race_user_2')
Familia.dbclient.del(dbkey2)
result = RaceConditionUser.find_by_dbkey(dbkey2, check_exists: false)
still_in_instances = RaceConditionUser.instances.members.include?('race_user_2')
[result, still_in_instances]
#=> [nil, true]

# --- TTL Expiration Tests ---

## TTL expiration leaves stale instances entry
session = RaceConditionSession.new(session_id: 'ttl_session_1', data: 'test data')
session.save
session.expire(1)
in_instances_before = RaceConditionSession.instances.members.include?('ttl_session_1')
sleep(1.5)
key_exists = Familia.dbclient.exists(RaceConditionSession.dbkey('ttl_session_1')).positive?
in_instances_still = RaceConditionSession.instances.members.include?('ttl_session_1')
[in_instances_before, key_exists, in_instances_still]
#=> [true, false, true]

## find does not clean up after TTL expiration (read-only)
result = RaceConditionSession.find_by_dbkey(RaceConditionSession.dbkey('ttl_session_1'))
in_instances_after = RaceConditionSession.instances.members.include?('ttl_session_1')
[result, in_instances_after]
#=> [nil, true]

## explicit cleanup after TTL expiration
RaceConditionSession.cleanup_stale_instance_entry(RaceConditionSession.dbkey('ttl_session_1'))
RaceConditionSession.instances.members.include?('ttl_session_1')
#=> false

## find_by_id after TTL also does not clean up
session2 = RaceConditionSession.new(session_id: 'ttl_session_2', data: 'test data 2')
session2.save
session2.expire(1)
sleep(1.5)
result = RaceConditionSession.find_by_id('ttl_session_2')
still_there = RaceConditionSession.instances.members.include?('ttl_session_2')
[result, still_there]
#=> [nil, true]

# --- Count Consistency Tests ---

## count includes phantom entries (find does not clean up)
RaceConditionUser.instances.clear
real = RaceConditionUser.new(user_id: 'count_real', name: 'Real', email: 'real@example.com')
real.save
RaceConditionUser.instances.add('count_phantom_1', Familia.now)
RaceConditionUser.instances.add('count_phantom_2', Familia.now)
count_before = RaceConditionUser.count
RaceConditionUser.find_by_id('count_phantom_1')
RaceConditionUser.find_by_id('count_phantom_2')
count_after = RaceConditionUser.count
real.destroy!
[count_before, count_after]
#=> [3, 3]

## keys_count vs count divergence with phantoms
RaceConditionUser.instances.clear
real2 = RaceConditionUser.new(user_id: 'keys_count_real', name: 'Real', email: 'real@example.com')
real2.save
RaceConditionUser.instances.add('keys_count_phantom', Familia.now)
count_before = RaceConditionUser.count
keys_count_before = RaceConditionUser.keys_count
# Find does not clean up — count stays the same
RaceConditionUser.find_by_id('keys_count_phantom')
count_after = RaceConditionUser.count
keys_count_after = RaceConditionUser.keys_count
real2.destroy!
[count_before, keys_count_before, count_after, keys_count_after]
#=> [2, 1, 2, 1]

# --- Edge Cases ---

## empty identifier in key doesn't cause issues
malformed_key = "#{RaceConditionUser.prefix}::object"
result = RaceConditionUser.find_by_dbkey(malformed_key)
result
#=> nil

## key with unusual identifier characters
RaceConditionUser.instances.add('user:with:colons', Familia.now)
result = RaceConditionUser.find_by_dbkey(RaceConditionUser.dbkey('user:with:colons'))
result
#=> nil

## concurrent load attempts on same stale entry — all return nil, entry persists
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

all_nil = results.all?(&:nil?)
still_in = RaceConditionUser.instances.members.include?('concurrent_phantom')
[all_nil, still_in, results.size]
#=> [true, true, 5]

# --- Cleanup ---

RaceConditionUser.instances.clear
RaceConditionSession.instances.clear
