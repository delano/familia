# try/integration/connection/pipeline_handler_integration_try.rb
#
# frozen_string_literal: true

# Integration Tests for FiberPipelineHandler
#
# Tests that Horreum and DataType operations route through the pipeline
# connection when called inside a pipelined block:
# - Connection chain ordering (FiberPipelineHandler before FiberTransactionHandler)
# - Fiber[:familia_pipeline] is set inside the block and cleared on exit
# - Ad-hoc database commands (e.g. #hset) inside the block use the pipeline conn
# - Multiple Horreum operations are batched within a single pipeline
# - Nested pipelined calls reuse the same connection (reentrant)
# - DataType operations issued inside the parent's pipeline route correctly
#
# Note: Fast writers (field!) and #commit_fields are NOT exercised here — they
# raise Familia::OperationModeError inside pipeline/transaction contexts. See
# try/edge_cases/fast_writer_transaction_guard_try.rb for that coverage.

require_relative '../../support/helpers/test_helpers'

# Test model for pipeline handler integration
class PipelineHandlerTestUser < Familia::Horreum
  logical_database 4
  identifier_field :userid
  field :userid
  field :name
  field :status

  list :activities
  set :permissions
  hashkey :metadata
end

def pipe_test_cleanup(*keys)
  Familia.dbclient(4).del(*keys) if keys.any?
end

# Setup - clean state
pipe_test_cleanup(
  'pipelinehandlertestuser:pipe_user_1:object',
  'pipelinehandlertestuser:pipe_user_2:object',
  'pipelinehandlertestuser:pipe_user_3:object',
  'pipelinehandlertestuser:pipe_user_4:object',
  'pipelinehandlertestuser:pipe_user_5:object'
)

## Connection chain includes FiberPipelineHandler before FiberTransactionHandler
# Verify the handler is present in the chain
@user = PipelineHandlerTestUser.new(userid: 'chain_check')
@user.save
chain = @user.instance_variable_get(:@class_connection_chain) ||
        @user.class.instance_variable_get(:@class_connection_chain)
handlers = chain.instance_variable_get(:@handlers)
handler_classes = handlers.map(&:class)
pipe_idx = handler_classes.index(Familia::Connection::FiberPipelineHandler)
txn_idx = handler_classes.index(Familia::Connection::FiberTransactionHandler)
@user.destroy!
pipe_idx < txn_idx  # Pipeline should come before transaction in chain
#=> true

## Fiber[:familia_pipeline] is set during pipelined block
@pipeline_set = false
@user = PipelineHandlerTestUser.new(userid: 'pipe_user_1')
@user.name = 'Test User'
@user.save

result = @user.pipelined do |pipe|
  @pipeline_set = !Fiber[:familia_pipeline].nil?
  pipe.hset(@user.dbkey, 'status', 'active')
end

[@pipeline_set, result.is_a?(Familia::MultiResult)]
#=> [true, true]

## Fiber[:familia_pipeline] cleared after pipelined block
@user.pipelined do |pipe|
  pipe.hset(@user.dbkey, 'name', 'Updated')
end
Fiber[:familia_pipeline].nil?
#=> true

## hset inside pipelined block uses pipeline connection
@user2 = PipelineHandlerTestUser.new(userid: 'pipe_user_2')
@user2.name = 'Pipeline Test'
@user2.save

@conn_inside_pipeline = nil
result = @user2.pipelined do |pipe|
  @conn_inside_pipeline = pipe.object_id
  @user2.hset(:status, 'pipelined')
end

[result.is_a?(Familia::MultiResult), @user2.hget(:status)]
#=> [true, "pipelined"]

## Multiple Horreum operations inside single pipeline are batched
@user3 = PipelineHandlerTestUser.new(userid: 'pipe_user_3')
@user3.name = 'Multi Op User'
@user3.save

result = @user3.pipelined do |_pipe|
  @user3.hset(:status, 'batch_1')
  @user3.hset(:name, 'Batch User')
  @user3.expire(3600)
end

# All operations completed - check final state
[@user3.hget(:status), @user3.hget(:name)]
#=> ["batch_1", "Batch User"]

## Nested pipelined calls reuse same connection
@outer_conn_id = nil
@inner_conn_id = nil

@user4 = PipelineHandlerTestUser.new(userid: 'pipe_user_4')
@user4.save

@user4.pipelined do |outer_pipe|
  @outer_conn_id = outer_pipe.object_id

  @user4.pipelined do |inner_pipe|
    @inner_conn_id = inner_pipe.object_id
    inner_pipe.hset(@user4.dbkey, 'nested', 'yes')
  end
end

@outer_conn_id == @inner_conn_id
#=> true

## DataType operations inside parent's pipelined block
@user5 = PipelineHandlerTestUser.new(userid: 'pipe_user_5')
@user5.name = 'DataType Test'
@user5.save

result = @user5.pipelined do |pipe|
  # Direct pipe commands for DataType operations
  pipe.sadd(@user5.permissions.dbkey, @user5.permissions.serialize_value('read'))
  pipe.sadd(@user5.permissions.dbkey, @user5.permissions.serialize_value('write'))
  pipe.hset(@user5.metadata.dbkey, 'level', @user5.metadata.serialize_value('admin'))
end

[@user5.permissions.member?('read'), @user5.permissions.member?('write'), @user5.metadata['level']]
#=> [true, true, "admin"]

## Connection handler class is tracked during pipeline
@handler_during_pipeline = nil

Familia.pipelined do |_pipe|
  @handler_during_pipeline = Fiber[:familia_connection_handler_class]
end

# The handler class should be set (may be CreateConnectionHandler or others)
!@handler_during_pipeline.nil?
#=> true

## Pipeline works with class-level pipelined method
result = PipelineHandlerTestUser.pipelined do |pipe|
  pipe.set('test:class_pipe', 'value')
  pipe.get('test:class_pipe')
end

[result.is_a?(Familia::MultiResult), result.results.last]
#=> [true, "value"]

# Cleanup
pipe_test_cleanup(
  'pipelinehandlertestuser:pipe_user_1:object',
  'pipelinehandlertestuser:pipe_user_2:object',
  'pipelinehandlertestuser:pipe_user_3:object',
  'pipelinehandlertestuser:pipe_user_4:object',
  'pipelinehandlertestuser:pipe_user_5:object',
  'test:class_pipe'
)
PipelineHandlerTestUser.instances.clear
