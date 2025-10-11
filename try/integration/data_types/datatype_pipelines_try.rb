# DataType Pipeline Support Tryouts
#
# Tests pipeline support for DataType objects. Pipelines provide performance
# optimization by batching commands without the atomicity guarantee of transactions.

require_relative '../../support/helpers/test_helpers'

# Setup
class PipelineTestUser < Familia::Horreum
  logical_database 4
  identifier_field :userid
  field :userid
  field :name

  sorted_set :scores
  hashkey :profile
  set :tags
  counter :visits
end

@user = PipelineTestUser.new(userid: 'pipe_user_001')
@user.name = 'Pipeline Tester'
@user.save

## Parent-owned SortedSet can execute pipeline
result = @user.scores.pipelined do |pipe|
  pipe.zadd(@user.scores.dbkey, 100, 'p1')
  pipe.zadd(@user.scores.dbkey, 200, 'p2')
  pipe.zcard(@user.scores.dbkey)
end
[result.is_a?(MultiResult), @user.scores.members.size]
#=> [true, 2]

## Parent-owned HashKey can execute pipeline
result = @user.profile.pipelined do |pipe|
  pipe.hset(@user.profile.dbkey, 'city', 'NYC')
  pipe.hset(@user.profile.dbkey, 'state', 'NY')
  pipe.hgetall(@user.profile.dbkey)
end
[result.is_a?(MultiResult), @user.profile.keys.sort]
#=> [true, ["city", "state"]]

## Standalone SortedSet can execute pipeline
leaderboard = Familia::SortedSet.new('pipeline:leaderboard')
leaderboard.delete!
result = leaderboard.pipelined do |pipe|
  pipe.zadd(leaderboard.dbkey, 100, 'player1')
  pipe.zadd(leaderboard.dbkey, 200, 'player2')
  pipe.zcard(leaderboard.dbkey)
end
[result.is_a?(MultiResult), leaderboard.members.size]
#=> [true, 2]

## Pipeline with direct_access works correctly
result = @user.profile.pipelined do |pipe_conn|
  pipe_conn.hset(@user.profile.dbkey, 'pipeline_test', 'yes')

  @user.profile.direct_access do |conn, key|
    conn.object_id == pipe_conn.object_id &&
    conn.hset(key, 'direct_test', 'yes')
  end
end
[@user.profile['pipeline_test'], @user.profile['direct_test']]
#=> ["yes", "yes"]

## Pipeline returns MultiResult with correct structure
result = @user.scores.pipelined do |pipe|
  pipe.zadd(@user.scores.dbkey, 300, 'p3')
  pipe.zadd(@user.scores.dbkey, 400, 'p4')
end
[result.is_a?(MultiResult), result.results.is_a?(Array)]
#=> [true, true]

## Empty pipeline returns empty MultiResult
result = @user.scores.pipelined { |pipe| }
[result.is_a?(MultiResult), result.results.empty?]
#=> [true, true]

## Multiple DataType operations in single pipeline
result = @user.scores.pipelined do |pipe|
  pipe.zadd(@user.scores.dbkey, 500, 'multi')
  pipe.hset(@user.profile.dbkey, 'multi', 'pipeline')
  pipe.sadd(@user.tags.dbkey, 'multi_tag')
end
[
  result.is_a?(MultiResult),
  @user.scores.member?('multi'),
  @user.profile['multi'],
  @user.tags.member?('multi_tag')
]
#=> [true, true, "pipeline", true]

## Standalone HashKey with logical_database option
custom = Familia::HashKey.new('pipeline:custom', logical_database: 5)
custom.delete!
result = custom.pipelined do |pipe|
  pipe.hset(custom.dbkey, 'key1', 'value1')
  pipe.hget(custom.dbkey, 'key1')
end
result.is_a?(MultiResult)
#=> true

# Cleanup
@user.destroy!
