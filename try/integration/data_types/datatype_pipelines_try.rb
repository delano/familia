# try/integration/data_types/datatype_pipelines_try.rb
#
# frozen_string_literal: true

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
[result.is_a?(Familia::MultiResult), @user.scores.members.size]
#=> [true, 2]

## Parent-owned HashKey can execute pipeline
result = @user.profile.pipelined do |pipe|
  pipe.hset(@user.profile.dbkey, 'city', 'NYC')
  pipe.hset(@user.profile.dbkey, 'state', 'NY')
  pipe.hgetall(@user.profile.dbkey)
end
[result.is_a?(Familia::MultiResult), @user.profile.keys.sort]
#=> [true, ["city", "state"]]

## Standalone SortedSet can execute pipeline
leaderboard = Familia::SortedSet.new('pipeline:leaderboard')
leaderboard.delete!
result = leaderboard.pipelined do |pipe|
  pipe.zadd(leaderboard.dbkey, 100, 'player1')
  pipe.zadd(leaderboard.dbkey, 200, 'player2')
  pipe.zcard(leaderboard.dbkey)
end
[result.is_a?(Familia::MultiResult), leaderboard.members.size]
#=> [true, 2]

## DataType operations inside a pipeline route through the pipeline connection
# HashKey#[]= and Fiber[:familia_pipeline] should agree: the pipeline
# connection is what receives the writes. Raw pipe.hset bypasses
# serialize_value, so 'yes' is stored as a bare string.
@user.profile.pipelined do |pipe_conn|
  pipe_conn.hset(@user.profile.dbkey, 'pipeline_test', 'yes')

  # The DataType wrapper's mutating methods auto-route to Fiber[:familia_pipeline]
  @user.profile['direct_test'] = 'yes'

  # The Fiber-local exposes the same connection used by the wrapper
  pipe_conn.object_id == Fiber[:familia_pipeline].object_id
end
[@user.profile['pipeline_test'], @user.profile['direct_test']]
#=> ["yes", "yes"]

## Pipeline returns Familia::MultiResult with correct structure
result = @user.scores.pipelined do |pipe|
  pipe.zadd(@user.scores.dbkey, 300, 'p3')
  pipe.zadd(@user.scores.dbkey, 400, 'p4')
end
[result.is_a?(Familia::MultiResult), result.results.is_a?(Array)]
#=> [true, true]

## Empty pipeline returns empty Familia::MultiResult
result = @user.scores.pipelined { |pipe| }
[result.is_a?(Familia::MultiResult), result.results.empty?]
#=> [true, true]

## Multiple DataType operations in single pipeline
# Note: Raw Redis commands bypass Familia's JSON serialization.
# Use serialize_value for values that will be looked up via Familia methods.
result = @user.scores.pipelined do |pipe|
  pipe.zadd(@user.scores.dbkey, 500, @user.scores.serialize_value('multi'))
  pipe.hset(@user.profile.dbkey, 'multi', @user.profile.serialize_value('pipeline'))
  pipe.sadd(@user.tags.dbkey, @user.tags.serialize_value('multi_tag'))
end
[
  result.is_a?(Familia::MultiResult),
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
result.is_a?(Familia::MultiResult)
#=> true

## DataType call site raises ConflictingContextError when pipeline+transaction nest
# Routing through the DataType chain must surface the same conflict semantics as
# Horreum (FiberPipelineHandler raises if Fiber[:familia_transaction] is also set).
error_raised = begin
  @user.profile.pipelined do |_pipe|
    @user.profile.transaction do |_txn|
      # Should not reach here — handler should raise before yielding
    end
  end
  false
rescue Familia::ConflictingContextError
  true
end
error_raised
#=> true

# Cleanup
@user.destroy!
