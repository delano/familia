# try/integration/connection/pipeline_horreum_routing_try.rb
#
# frozen_string_literal: true

# Pipeline Routing Tests for Horreum Operations
#
# Tests that Horreum methods properly route through the pipeline when
# called inside pipelined blocks. This is the critical integration that
# FiberPipelineHandler enables.
#
# Covers:
# - hset/hmset inside pipelined blocks
# - expire inside pipelined blocks
# - Mixed Horreum and DataType operations
# - Connection routing via FiberPipelineHandler
#
# NOTE: Fast writers (field!) and commit_fields have limitations inside
# pipelines due to Redis::Future return values. Those edge cases are
# documented separately.

require_relative '../../support/helpers/test_helpers'

# Test model for Horreum pipeline routing
class PipelineRoutingTestModel < Familia::Horreum
  logical_database 4
  identifier_field :modelid

  field :modelid
  field :name
  field :status
  field :counter

  list :log_entries
  set :flags
  hashkey :settings
end

def routing_test_cleanup(*keys)
  Familia.dbclient(4).del(*keys) if keys.any?
end

# Setup
@test_keys = []

## hset inside pipelined uses pipeline connection
@model1 = PipelineRoutingTestModel.new(modelid: 'routing_model_1')
@model1.save
@test_keys << @model1.dbkey

result = @model1.pipelined do |pipe|
  @model1.hset(:name, 'Direct hset')
  @model1.hset(:status, 'hset_active')
end

[@model1.hget(:name), @model1.hget(:status)]
#=> ["Direct hset", "hset_active"]

## hmset inside pipelined uses pipeline connection
@model2 = PipelineRoutingTestModel.new(modelid: 'routing_model_2')
@model2.save
@test_keys << @model2.dbkey

result = @model2.pipelined do |_pipe|
  @model2.hmset(name: 'Bulk Set', status: 'bulk_active', counter: '100')
end

[@model2.hget(:name), @model2.hget(:status), @model2.hget(:counter)]
#=> ["Bulk Set", "bulk_active", "100"]

## Pipeline with mixed Horreum and DataType operations
@model3 = PipelineRoutingTestModel.new(modelid: 'routing_model_3')
@model3.name = 'Mixed Ops'
@model3.save
@test_keys << @model3.dbkey
@test_keys << @model3.flags.dbkey
@test_keys << @model3.settings.dbkey

result = @model3.pipelined do |pipe|
  # Horreum operation
  @model3.hset(:status, 'mixed')

  # DataType operations via raw commands
  pipe.sadd(@model3.flags.dbkey, @model3.flags.serialize_value('important'))
  pipe.hset(@model3.settings.dbkey, 'theme', @model3.settings.serialize_value('dark'))
end

[@model3.hget(:status), @model3.flags.member?('important'), @model3.settings['theme']]
#=> ["mixed", true, "dark"]

## Pipelined block returns MultiResult
@model4 = PipelineRoutingTestModel.new(modelid: 'routing_model_4')
@model4.save
@test_keys << @model4.dbkey

result = @model4.pipelined do |pipe|
  pipe.hset(@model4.dbkey, 'name', 'Result Test')
  pipe.hget(@model4.dbkey, 'name')
end

[result.is_a?(MultiResult), result.results.is_a?(Array)]
#=> [true, true]

## Empty pipelined block returns empty MultiResult
@model5 = PipelineRoutingTestModel.new(modelid: 'routing_model_5')
@model5.save
@test_keys << @model5.dbkey

result = @model5.pipelined { |_pipe| }
[result.is_a?(MultiResult), result.results.empty?]
#=> [true, true]

## Transaction inside pipelined block raises ConflictingContextError
@model6 = PipelineRoutingTestModel.new(modelid: 'routing_model_6')
@model6.save
@test_keys << @model6.dbkey

error_raised = begin
  @model6.pipelined do |pipe|
    pipe.hset(@model6.dbkey, 'before_txn', 'yes')
    @model6.transaction do |txn|
      txn.hset(@model6.dbkey, 'in_txn', 'yes')
    end
  end
  false
rescue Familia::ConflictingContextError
  true
end
error_raised
#=> true

## expire inside pipelined uses pipeline
@model7 = PipelineRoutingTestModel.new(modelid: 'routing_model_7')
@model7.name = 'Expire Test'
@model7.save
@test_keys << @model7.dbkey

result = @model7.pipelined do |_pipe|
  @model7.expire(7200)
end

# TTL should be set (value depends on timing, just check it's positive)
@model7.current_expiration > 0
#=> true

# Cleanup
routing_test_cleanup(*@test_keys.uniq)
PipelineRoutingTestModel.instances.clear
