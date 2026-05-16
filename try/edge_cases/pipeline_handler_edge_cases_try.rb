# try/edge_cases/pipeline_handler_edge_cases_try.rb
#
# frozen_string_literal: true

# Edge Case Tests for FiberPipelineHandler
#
# Tests edge cases and error handling:
# - Pipelined block with transaction inside
# - Error handling when pipeline fails mid-batch
# - Connection chain precedence (pipeline before transaction handler)
# - Cleanup after exceptions
# - Fiber isolation

require_relative '../support/helpers/test_helpers'

# Test model for edge cases
class PipelineEdgeCaseModel < Familia::Horreum
  logical_database 4
  identifier_field :modelid

  field :modelid
  field :name
  field :value
end

def edge_cleanup(*keys)
  Familia.dbclient(4).del(*keys) if keys.any?
end

# Setup
edge_cleanup(
  'pipelineedgecasemodel:edge_1:object',
  'pipelineedgecasemodel:edge_2:object',
  'pipelineedgecasemodel:edge_3:object',
  'pipelineedgecasemodel:edge_4:object',
  'pipelineedgecasemodel:edge_5:object'
)

## Pipeline clears Fiber local after successful completion
Familia.pipelined do |pipe|
  pipe.set('test:edge_cleanup', 'value')
end
Fiber[:familia_pipeline].nil?
#=> true

## Pipeline clears Fiber local after exception
begin
  Familia.pipelined do |_pipe|
    raise 'Intentional test error'
  end
rescue => e
  # Expected
end

Fiber[:familia_pipeline].nil?
#=> true

## Pipeline handler returns nil outside pipeline block
Fiber[:familia_pipeline] = nil
result = Familia::Connection::FiberPipelineHandler.instance.handle(nil)
result.nil?
#=> true

## Pipeline connection is different from regular connection
@pipeline_conn = nil
@regular_conn = Familia.dbclient

Familia.pipelined do |pipe|
  @pipeline_conn = pipe
end

@pipeline_conn.object_id != @regular_conn.object_id
#=> true

## Nested pipelines share same connection (reentrant)
@outer_id = nil
@inner_id = nil

Familia.pipelined do |outer|
  @outer_id = outer.object_id

  Familia.pipelined do |inner|
    @inner_id = inner.object_id
  end
end

@outer_id == @inner_id
#=> true

## Pipeline and transaction cannot be nested - raises ConflictingContextError
@model1 = PipelineEdgeCaseModel.new(modelid: 'edge_1')
@model1.save

error_raised = begin
  @model1.pipelined do |pipe|
    pipe.hset(@model1.dbkey, 'pipe_field', 'pipe_value')
    @model1.transaction do |txn|
      txn.hset(@model1.dbkey, 'txn_field', 'txn_value')
    end
  end
  false
rescue Familia::ConflictingContextError
  true
end
error_raised
#=> true

## Transaction and pipeline fiber locals are independent
@pipe_set = false
@txn_set = false

Familia.pipelined do |pipe|
  @pipe_set = !Fiber[:familia_pipeline].nil?
  @txn_set_in_pipe = Fiber[:familia_transaction].nil?
end

Familia.transaction do |txn|
  @txn_set = !Fiber[:familia_transaction].nil?
  @pipe_set_in_txn = Fiber[:familia_pipeline].nil?
end

[@pipe_set, @txn_set_in_pipe, @txn_set, @pipe_set_in_txn]
#=> [true, true, true, true]

## Multiple sequential pipelines each get fresh context
@conn_ids = []

3.times do
  Familia.pipelined do |pipe|
    @conn_ids << pipe.object_id
  end
end

# Connections may or may not be same (depends on pool) but each pipeline completes
@conn_ids.size == 3
#=> true

## Pipeline returns all command results
result = Familia.pipelined do |pipe|
  pipe.set('test:edge_multi_1', 'a')
  pipe.set('test:edge_multi_2', 'b')
  pipe.get('test:edge_multi_1')
  pipe.get('test:edge_multi_2')
end

result.results.last(2)
#=> ["a", "b"]

## Pipeline with no commands returns empty results
result = Familia.pipelined { |_pipe| }
result.results
#=> []

## Handler allows_pipelined is :reentrant not true
Familia::Connection::FiberPipelineHandler.allows_pipelined == :reentrant
#=> true

## Handler allows_transaction is false (cannot start transaction on pipeline connection)
Familia::Connection::FiberPipelineHandler.allows_transaction == false
#=> true

## FiberPipelineHandler comes before FiberTransactionHandler in connection chain
# This ensures pipeline connections are detected before transaction connections
@model2 = PipelineEdgeCaseModel.new(modelid: 'edge_2')
@model2.save

chain = @model2.class.instance_variable_get(:@class_connection_chain)
handlers = chain.instance_variable_get(:@handlers)
handler_classes = handlers.map(&:class)

pipe_index = handler_classes.index(Familia::Connection::FiberPipelineHandler)
txn_index = handler_classes.index(Familia::Connection::FiberTransactionHandler)

# Pipeline handler should come first (lower index = higher priority)
pipe_index < txn_index
#=> true

## Deeply nested pipelines all share same connection
@ids = []

Familia.pipelined do |p1|
  @ids << p1.object_id
  Familia.pipelined do |p2|
    @ids << p2.object_id
    Familia.pipelined do |p3|
      @ids << p3.object_id
    end
  end
end

@ids.uniq.size == 1
#=> true

## Pipeline works with different logical databases
model_db4 = PipelineEdgeCaseModel.new(modelid: 'edge_3')
model_db4.save

result = model_db4.pipelined do |pipe|
  pipe.hset(model_db4.dbkey, 'db4_field', 'db4_value')
end

result.is_a?(Familia::MultiResult)
#=> true

# Cleanup
edge_cleanup(
  'pipelineedgecasemodel:edge_1:object',
  'pipelineedgecasemodel:edge_2:object',
  'pipelineedgecasemodel:edge_3:object',
  'test:edge_cleanup',
  'test:edge_multi_1',
  'test:edge_multi_2'
)
PipelineEdgeCaseModel.instances.clear
