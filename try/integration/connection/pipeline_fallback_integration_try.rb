#
# Tests pipeline fallback modes when connection handlers don't support pipelines.
# Validates that pipeline_mode configuration works correctly with cached connections
# and that the fallback behavior matches transaction fallback patterns.
#

require_relative '../../support/helpers/test_helpers'

# Store original values
$original_pipeline_mode = Familia.pipeline_mode
$original_transaction_mode = Familia.transaction_mode

# Test model for pipeline fallback scenarios
class PipelineFallbackTest < Familia::Horreum
  identifier_field :testid
  field :testid
end

## Test 1: Strict mode raises error with cached connection
Familia.configure { |c| c.pipeline_mode = :strict }

# Cache connection at class level (uses DefaultConnectionHandler which doesn't support pipelines)
PipelineFallbackTest.instance_variable_set(:@dbclient, Familia.create_dbclient)

customer = PipelineFallbackTest.new(testid: 'strict_test')
customer.pipelined { |c| c.set('key', 'value') }
#=:> Familia::OperationModeError
#=~> /Cannot start pipeline with.*CachedConnectionHandler/

## Test 2: Warn mode falls back successfully with cached connection
Familia.configure { |c| c.pipeline_mode = :warn }

# Cache connection at class level
PipelineFallbackTest.instance_variable_set(:@dbclient, Familia.create_dbclient)

customer2 = PipelineFallbackTest.new(testid: 'warn_test')
$warn_result = customer2.pipelined do |conn|
  conn.set(customer2.dbkey('field1'), 'value1')
  conn.set(customer2.dbkey('field2'), 'value2')
  conn.get(customer2.dbkey('field1'))
end
$warn_result.successful?
#=> true

## Test 2b: Warn mode result contains all command results
$warn_result.results.size
#=> 3

## Test 2c: Warn mode result contains correct value
$warn_result.results[2]
#=> 'value1'

## Test 3: Fresh connections still support real pipelines in strict mode
Familia.configure { |c| c.pipeline_mode = :strict }

# Clear cached class-level connection to force CreateConnectionHandler
PipelineFallbackTest.remove_instance_variable(:@dbclient) if PipelineFallbackTest.instance_variable_defined?(:@dbclient)

customer3 = PipelineFallbackTest.new(testid: 'fresh_test')
$fresh_result = customer3.pipelined do |conn|
  conn.set('pipeline_key1', 'val1')
  conn.set('pipeline_key2', 'val2')
  conn.get('pipeline_key1')
end
$fresh_result.successful?
#=> true

## Test 3b: Real pipeline returns correct result count
$fresh_result.results.size
#=> 3

## Test 4: MultiResult format is correct for fallback
Familia.configure { |c| c.pipeline_mode = :permissive }

# Cache connection at class level
PipelineFallbackTest.instance_variable_set(:@dbclient, Familia.create_dbclient)

customer4 = PipelineFallbackTest.new(testid: 'multiresult_test')
$multi_result = customer4.pipelined do |conn|
  conn.set(customer4.dbkey('test'), 'value')
  conn.get(customer4.dbkey('test'))
end
$multi_result.class.name
#=> 'MultiResult'

## Test 4b: MultiResult successful? returns correct value
$multi_result.successful?
#=> true

## Test 4c: MultiResult results is an Array
$multi_result.results.class
#=> Array

## Test 5: Permissive mode silently falls back
Familia.configure { |c| c.pipeline_mode = :permissive }

# Cache connection at class level
PipelineFallbackTest.instance_variable_set(:@dbclient, Familia.create_dbclient)

customer5 = PipelineFallbackTest.new(testid: 'permissive_test')
$permissive_result = customer5.pipelined do |conn|
  conn.set(customer5.dbkey('counter'), '0')
  conn.incr(customer5.dbkey('counter'))
  conn.get(customer5.dbkey('counter'))
end
$permissive_result.successful?
#=> true

## Test 5b: Permissive mode result contains correct values
$permissive_result.results
#=> ['OK', 1, '1']

## Test 6: Pipeline mode configuration validation
Familia.configure { |c| c.pipeline_mode = :invalid }
#=:> ArgumentError
#=~> /Pipeline mode must be :strict, :warn, or :permissive/

## Test 7: Default pipeline_mode is :warn
Familia.instance_variable_set(:@pipeline_mode, nil)
Familia.pipeline_mode
#=> :warn

## Cleanup: Restore original values
Familia.configure do |c|
  c.pipeline_mode = $original_pipeline_mode
  c.transaction_mode = $original_transaction_mode
end
PipelineFallbackTest.remove_instance_variable(:@dbclient) if PipelineFallbackTest.instance_variable_defined?(:@dbclient)
