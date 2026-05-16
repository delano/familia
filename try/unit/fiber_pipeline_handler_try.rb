# try/unit/fiber_pipeline_handler_try.rb
#
# frozen_string_literal: true

# Unit Tests for FiberPipelineHandler
#
# Tests the FiberPipelineHandler in isolation, verifying:
# - Returns nil when Fiber[:familia_pipeline] is not set
# - Returns the pipeline connection when Fiber[:familia_pipeline] is set
# - Correct allows_transaction and allows_pipelined flags
# - Singleton pattern works correctly
#
# These tests focus on the handler behavior itself, not integration with Horreum.

require_relative '../support/helpers/test_helpers'

## FiberPipelineHandler singleton instance is frozen
Familia::Connection::FiberPipelineHandler.instance.frozen?
#=> true

## FiberPipelineHandler singleton returns same instance
handler1 = Familia::Connection::FiberPipelineHandler.instance
handler2 = Familia::Connection::FiberPipelineHandler.instance
handler1.object_id == handler2.object_id
#=> true

## FiberPipelineHandler allows_transaction is false
Familia::Connection::FiberPipelineHandler.allows_transaction
#=> false

## FiberPipelineHandler allows_pipelined is :reentrant
Familia::Connection::FiberPipelineHandler.allows_pipelined
#=> :reentrant

## FiberPipelineHandler returns nil when Fiber[:familia_pipeline] not set
original = Fiber[:familia_pipeline]
Fiber[:familia_pipeline] = nil
result = Familia::Connection::FiberPipelineHandler.instance.handle(nil)
Fiber[:familia_pipeline] = original
result
#=> nil

## FiberPipelineHandler returns nil with URI when Fiber[:familia_pipeline] not set
original = Fiber[:familia_pipeline]
Fiber[:familia_pipeline] = nil
result = Familia::Connection::FiberPipelineHandler.instance.handle('redis://localhost:6379')
Fiber[:familia_pipeline] = original
result
#=> nil

## FiberPipelineHandler returns pipeline connection when set
@mock_pipeline = Object.new
original = Fiber[:familia_pipeline]
Fiber[:familia_pipeline] = @mock_pipeline
result = Familia::Connection::FiberPipelineHandler.instance.handle(nil)
Fiber[:familia_pipeline] = original
result.object_id == @mock_pipeline.object_id
#=> true

## FiberPipelineHandler returns pipeline regardless of URI argument
@mock_pipeline = Object.new
original = Fiber[:familia_pipeline]
Fiber[:familia_pipeline] = @mock_pipeline
result = Familia::Connection::FiberPipelineHandler.instance.handle('redis://different:6380/5')
Fiber[:familia_pipeline] = original
result.object_id == @mock_pipeline.object_id
#=> true

## FiberPipelineHandler includes the Handler interface module
Familia::Connection::FiberPipelineHandler.include?(Familia::Connection::Handler)
#=> true

## FiberPipelineHandler instance responds to handle
Familia::Connection::FiberPipelineHandler.instance.respond_to?(:handle)
#=> true

## FiberPipelineHandler class has singleton accessor
Familia::Connection::FiberPipelineHandler.respond_to?(:instance)
#=> true

## FiberPipelineHandler different from FiberTransactionHandler
handler1 = Familia::Connection::FiberPipelineHandler.instance
handler2 = Familia::Connection::FiberTransactionHandler.instance
handler1.object_id != handler2.object_id
#=> true

## FiberPipelineHandler and FiberTransactionHandler have opposite flags
pipe_txn = Familia::Connection::FiberPipelineHandler.allows_transaction
pipe_pipe = Familia::Connection::FiberPipelineHandler.allows_pipelined
txn_txn = Familia::Connection::FiberTransactionHandler.allows_transaction
txn_pipe = Familia::Connection::FiberTransactionHandler.allows_pipelined
[pipe_txn, pipe_pipe, txn_txn, txn_pipe]
#=> [false, :reentrant, :reentrant, false]

## FiberPipelineHandler raises ConflictingContextError when both contexts are set
@pipe_conn = Object.new
@txn_conn = Object.new
original_pipe = Fiber[:familia_pipeline]
original_txn = Fiber[:familia_transaction]

Fiber[:familia_pipeline] = @pipe_conn
Fiber[:familia_transaction] = @txn_conn

error_raised = begin
  Familia::Connection::FiberPipelineHandler.instance.handle(nil)
  false
rescue Familia::ConflictingContextError
  true
ensure
  Fiber[:familia_pipeline] = original_pipe
  Fiber[:familia_transaction] = original_txn
end
error_raised
#=> true

## FiberTransactionHandler raises ConflictingContextError when both contexts are set
@pipe_conn = Object.new
@txn_conn = Object.new
original_pipe = Fiber[:familia_pipeline]
original_txn = Fiber[:familia_transaction]

Fiber[:familia_pipeline] = @pipe_conn
Fiber[:familia_transaction] = @txn_conn

error_raised = begin
  Familia::Connection::FiberTransactionHandler.instance.handle(nil)
  false
rescue Familia::ConflictingContextError
  true
ensure
  Fiber[:familia_pipeline] = original_pipe
  Fiber[:familia_transaction] = original_txn
end
error_raised
#=> true

## Clearing Fiber[:familia_pipeline] makes handler return nil
@mock_pipeline = Object.new
original_txn = Fiber[:familia_transaction]
Fiber[:familia_transaction] = nil  # ensure no conflict
Fiber[:familia_pipeline] = @mock_pipeline
first_result = Familia::Connection::FiberPipelineHandler.instance.handle(nil)
Fiber[:familia_pipeline] = nil
second_result = Familia::Connection::FiberPipelineHandler.instance.handle(nil)
Fiber[:familia_transaction] = original_txn  # restore
[first_result.object_id == @mock_pipeline.object_id, second_result]
#=> [true, nil]
