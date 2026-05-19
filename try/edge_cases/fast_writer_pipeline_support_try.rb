require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Test class for fast writer pipeline/transaction support
class FastWriterPipelineTest < Familia::Horreum
  identifier_field :testid
  field :testid
  field :name
  field :planid
  field :region
end

# Clean slate
@obj = FastWriterPipelineTest.new(testid: 'fw-pipeline-test', name: 'initial', planid: 'old_plan')
@obj.destroy!
@obj.save

## Fast writer inside pipeline returns Redis::Future
result = nil
@obj.pipelined do
  result = @obj.planid!('new_plan_v1')
end
result.is_a?(Redis::Future)
#=> true

## Fast writer value is persisted after pipeline completes
@obj.refresh!
@obj.planid
#=> 'new_plan_v1'

## Multiple fast writers inside single pipeline all return Futures
results = []
@obj.pipelined do
  results << @obj.planid!('plan_v2')
  results << @obj.region!('ca-east-1')
end
results.all? { |r| r.is_a?(Redis::Future) }
#=> true

## Multiple fast writer values persisted after pipeline
@obj.refresh!
[@obj.planid, @obj.region]
#=> ['plan_v2', 'ca-east-1']

## Fast writer inside transaction returns Redis::Future
result = nil
@obj.transaction do
  result = @obj.name!('tx-updated')
end
result.is_a?(Redis::Future)
#=> true

## Fast writer value is persisted after transaction completes
@obj.refresh!
@obj.name
#=> 'tx-updated'

## touch_instances! is called during pipelined fast writer
@obj.class.instances.remove(@obj)
raise "Setup failed: should not be member" if @obj.class.instances.member?(@obj.identifier)
@obj.pipelined do
  @obj.planid!('plan_v3')
end
@obj.class.instances.member?(@obj.identifier)
#=> true

## touch_instances! is called during transaction fast writer
@obj.class.instances.remove(@obj)
raise "Setup failed: should not be member" if @obj.class.instances.member?(@obj.identifier)
@obj.transaction do
  @obj.name!('tx-touch-test')
end
@obj.class.instances.member?(@obj.identifier)
#=> true

## Cleanup
@obj.destroy!
true
#=> true
