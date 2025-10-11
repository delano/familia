# DataType Transaction Support Tryouts
#
# Tests transaction support for DataType objects, covering both parent-owned
# DataTypes (delegating to parent) and standalone DataTypes (managing their
# own connections). Validates atomic operations, connection context handling,
# and integration with the transaction mode system.

require_relative '../../support/helpers/test_helpers'

# Setup - Create test model with various DataType fields
class TransactionTestUser < Familia::Horreum
  logical_database 2
  identifier_field :userid
  field :userid
  field :name
  field :email

  # Instance-level DataTypes
  sorted_set :scores
  hashkey :profile
  set :tags
  list :activity
  counter :visits
  string :bio
end

@user = TransactionTestUser.new(userid: 'txn_user_001')
@user.name = 'Transaction Tester'
@user.save

## Parent-owned SortedSet can execute transaction
result = @user.scores.transaction do |conn|
  conn.zadd(@user.scores.dbkey, 100, 'level1')
  conn.zadd(@user.scores.dbkey, 200, 'level2')
  conn.zadd(@user.scores.dbkey, 300, 'level3')
end
[result.is_a?(MultiResult), @user.scores.members.sort]
#=> [true, ["level1", "level2", "level3"]]

## Parent-owned HashKey can execute transaction
result = @user.profile.transaction do |conn|
  conn.hset(@user.profile.dbkey, 'city', 'San Francisco')
  conn.hset(@user.profile.dbkey, 'country', 'USA')
  conn.hget(@user.profile.dbkey, 'city')
end
[result.is_a?(MultiResult), result.results.last, @user.profile['country']]
#=> [true, "San Francisco", "USA"]

## Parent-owned UnsortedSet can execute transaction
result = @user.tags.transaction do |conn|
  conn.sadd(@user.tags.dbkey, 'ruby')
  conn.sadd(@user.tags.dbkey, 'redis')
  conn.scard(@user.tags.dbkey)
end
[result.is_a?(MultiResult), result.results.last, @user.tags.members.sort]
#=> [true, 2, ["redis", "ruby"]]

## Parent-owned List can execute transaction
result = @user.activity.transaction do |conn|
  conn.rpush(@user.activity.dbkey, 'login')
  conn.rpush(@user.activity.dbkey, 'view_profile')
  conn.rpush(@user.activity.dbkey, 'logout')
  conn.llen(@user.activity.dbkey)
end
[result.is_a?(MultiResult), result.results.last, @user.activity.members]
#=> [true, 3, ["login", "view_profile", "logout"]]

## Parent-owned Counter can execute transaction
result = @user.visits.transaction do |conn|
  conn.set(@user.visits.dbkey, 0)
  conn.incr(@user.visits.dbkey)
  conn.incr(@user.visits.dbkey)
  conn.get(@user.visits.dbkey)
end
[result.is_a?(MultiResult), result.results.last.to_i, @user.visits.value]
#=> [true, 2, 2]

## Parent-owned StringKey can execute transaction
result = @user.bio.transaction do |conn|
  conn.set(@user.bio.dbkey, 'Ruby developer')
  conn.append(@user.bio.dbkey, ' and Redis enthusiast')
  conn.get(@user.bio.dbkey)
end
[result.is_a?(MultiResult), result.results.last, @user.bio.value]
#=> [true, "Ruby developer and Redis enthusiast", "Ruby developer and Redis enthusiast"]

## Standalone SortedSet can execute transaction
leaderboard = Familia::SortedSet.new('game:leaderboard')
leaderboard.delete!
result = leaderboard.transaction do |conn|
  conn.zadd(leaderboard.dbkey, 500, 'player1')
  conn.zadd(leaderboard.dbkey, 600, 'player2')
  conn.zadd(leaderboard.dbkey, 450, 'player3')
  conn.zcard(leaderboard.dbkey)
end
[result.is_a?(MultiResult), result.results.last, leaderboard.members.size]
#=> [true, 3, 3]

## Standalone HashKey can execute transaction
cache = Familia::HashKey.new('app:cache')
cache.delete!
result = cache.transaction do |conn|
  conn.hset(cache.dbkey, 'key1', 'value1')
  conn.hset(cache.dbkey, 'key2', 'value2')
  conn.hkeys(cache.dbkey)
end
[result.is_a?(MultiResult), result.results.last.sort, cache.keys.sort]
#=> [true, ["key1", "key2"], ["key1", "key2"]]

## Standalone UnsortedSet can execute transaction
global_tags = Familia::UnsortedSet.new('app:tags')
global_tags.delete!
result = global_tags.transaction do |conn|
  conn.sadd(global_tags.dbkey, 'tag1')
  conn.sadd(global_tags.dbkey, 'tag2')
  conn.smembers(global_tags.dbkey)
end
[result.is_a?(MultiResult), result.results.last.sort, global_tags.members.sort]
#=> [true, ["tag1", "tag2"], ["tag1", "tag2"]]

## Standalone StringKey can execute transaction
session_data = Familia::StringKey.new('session:abc123')
session_data.delete!
result = session_data.transaction do |conn|
  conn.set(session_data.dbkey, '{"user_id": 123}')
  conn.expire(session_data.dbkey, 3600)
  conn.get(session_data.dbkey)
end
[result.is_a?(MultiResult), result.results.last, session_data.value]
#=> [true, "{\"user_id\": 123}", "{\"user_id\": 123}"]

## Transaction with logical_database option works
custom_cache = Familia::HashKey.new('custom:cache', logical_database: 3)
custom_cache.delete!
result = custom_cache.transaction do |conn|
  conn.hset(custom_cache.dbkey, 'setting', 'enabled')
  conn.hget(custom_cache.dbkey, 'setting')
end
[result.is_a?(MultiResult), result.results.last]
#=> [true, "enabled"]

## Transaction provides correct connection object type
conn_class = nil
@user.scores.transaction do |conn|
  conn_class = conn.class.name
end
conn_class
#=> "Redis::MultiConnection"

## Transaction with direct_access works correctly
result = @user.profile.transaction do |trans_conn|
  trans_conn.hset(@user.profile.dbkey, 'status', 'active')

  # direct_access should use the same transaction connection
  @user.profile.direct_access do |conn, key|
    conn.object_id == trans_conn.object_id &&
    conn.hset(key, 'verified', 'true')
  end
end
[@user.profile['status'], @user.profile['verified']]
#=> ["active", "true"]

## Transaction atomicity - all commands succeed or none
test_zset = Familia::SortedSet.new('atomic:test')
test_zset.delete!
test_zset.add('initial', 1)

begin
  test_zset.transaction do |conn|
    conn.zadd(test_zset.dbkey, 100, 'member1')
    conn.zadd(test_zset.dbkey, 200, 'member2')
    raise 'Intentional error to test rollback'
  end
rescue => e
  # Transaction should have rolled back
  test_zset.members
end
#=> ["initial"]

## Nested transactions with parent-owned DataTypes work
outer_result = @user.scores.transaction do |outer_conn|
  outer_conn.zadd(@user.scores.dbkey, 999, 'outer_member')

  inner_result = @user.tags.transaction do |inner_conn|
    inner_conn.sadd(@user.tags.dbkey, 'nested_tag')
  end

  inner_result.is_a?(MultiResult)
end
[outer_result.is_a?(MultiResult), @user.tags.member?('nested_tag')]
#=> [true, true]

## Transaction respects transaction modes (permissive)
begin
  original_mode = Familia.transaction_mode
  Familia.configure { |config| config.transaction_mode = :permissive }

  # Force a cached connection to trigger fallback
  @user.class.instance_variable_set(:@dbclient, Familia.create_dbclient)

  result = @user.scores.transaction do |conn|
    # Should be IndividualCommandProxy in fallback mode
    conn.class == Familia::Connection::IndividualCommandProxy &&
    conn.zadd(@user.scores.dbkey, 888, 'fallback_test')
  end

  result.is_a?(MultiResult)
ensure
  @user.class.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = original_mode }
end
#=> true

## Transaction with empty block returns empty MultiResult
result = @user.scores.transaction { |conn| }
[result.is_a?(MultiResult), result.results.empty?]
#=> [true, true]

## Transaction connection uses parent's logical_database
# TransactionTestUser has logical_database 2
# Parent-owned DataType delegates to parent, verify via class setting
@user.scores.delete!
@user.scores.transaction do |conn|
  conn.zadd(@user.scores.dbkey, 1, 'test_member')
end
TransactionTestUser.logical_database
#=> 2

## Multiple DataType types in single transaction
result = @user.scores.transaction do |conn|
  # Can operate on different DataTypes using same connection
  conn.zadd(@user.scores.dbkey, 777, 'multi_test')
  conn.hset(@user.profile.dbkey, 'multi', 'yes')
  conn.sadd(@user.tags.dbkey, 'multi_tag')
  conn.rpush(@user.activity.dbkey, 'multi_action')
end
[
  result.is_a?(MultiResult),
  @user.scores.member?('multi_test'),
  @user.profile['multi'],
  @user.tags.member?('multi_tag'),
  @user.activity.members.include?('multi_action')
]
#=> [true, true, "yes", true, true]

# Cleanup
@user.destroy!
