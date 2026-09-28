# try/unit/utils/future_aware_helpers_try.rb
#
# frozen_string_literal: true

# Direct unit tests for the Future-aware utility methods in Familia::Utils:
# Familia.success?, Familia.positive?, Familia.transform_reply,
# Familia.transaction_or_pipeline? and Familia.assert_replies_available!.
#
# These methods handle two cases:
#   1. Concrete Integer return values from Redis commands
#   2. Redis::Future objects inside pipelines/transactions (passthrough)
#
# Call sites include fast writers, DEL operations, EXISTS checks,
# LINSERT results, and TTL comparisons.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

@test_key = 'familia:test:future_aware_helpers'

##
## Familia.success? — concrete values
##

## success? returns true for positive integer (new key created)
Familia.success?(1)
#=> true

## success? returns true for zero (existing key updated)
Familia.success?(0)
#=> true

## success? returns false for negative integer
Familia.success?(-1)
#=> false

## success? returns false for large negative
Familia.success?(-100)
#=> false

##
## Familia.positive? — concrete values
##

## positive? returns true for positive integer
Familia.positive?(1)
#=> true

## positive? returns true for large positive integer
Familia.positive?(5)
#=> true

## positive? returns false for zero (nothing happened)
Familia.positive?(0)
#=> false

## positive? returns false for negative integer
Familia.positive?(-1)
#=> false

##
## Redis::Future passthrough — inside a pipeline
##

## success? returns the Future unchanged inside a pipeline
@success_future = nil
Familia.dbclient.pipelined do |pipe|
  fut = pipe.hset(@test_key, 'field', 'val')
  @success_future = Familia.success?(fut)
end
@success_future.is_a?(Redis::Future)
#=> true

## success? Future resolves to a truthy result after pipeline completes
@success_future.value.zero? || @success_future.value.positive?
#=> true

## positive? returns the Future unchanged inside a pipeline
@positive_future = nil
Familia.dbclient.pipelined do |pipe|
  fut = pipe.exists(@test_key)
  @positive_future = Familia.positive?(fut)
end
@positive_future.is_a?(Redis::Future)
#=> true

## positive? Future resolves to truthy for an existing key after pipeline
@positive_future.value.positive?
#=> true

##
## Edge cases — nil and non-numeric raise NoMethodError
##

## success? raises for nil input (no guard — explicit contract)
begin
  Familia.success?(nil)
rescue NoMethodError => e
  e.class
end
#=> NoMethodError

## positive? raises for nil input
begin
  Familia.positive?(nil)
rescue NoMethodError => e
  e.class
end
#=> NoMethodError

## success? raises for string input
begin
  Familia.success?('ok')
rescue NoMethodError => e
  e.class
end
#=> NoMethodError

## positive? raises for string input
begin
  Familia.positive?('ok')
rescue NoMethodError => e
  e.class
end
#=> NoMethodError

##
## Familia.transform_reply
##

## transform_reply yields a concrete reply and returns the block result
Familia.transform_reply(%w[a b]) { |reply| reply.map(&:upcase) }
#=> ["A", "B"]

## transform_reply returns a Future untouched and does not run the block
@transform_ran = false
@transform_future = nil
Familia.dbclient.pipelined do |pipe|
  fut = pipe.hkeys(@test_key)
  @transform_future = Familia.transform_reply(fut) { @transform_ran = true }
end
[@transform_future.is_a?(Redis::Future), @transform_ran]
#=> [true, false]

## the passed-through Future resolves to the unconverted reply
@transform_future.value
#=> ["field"]

##
## Familia.transaction_or_pipeline? and Familia.assert_replies_available!
##

## transaction_or_pipeline? is false outside any block
Familia.transaction_or_pipeline?
#=> false

## transaction_or_pipeline? is true inside a Familia transaction
@inside_txn = nil
Familia.transaction { @inside_txn = Familia.transaction_or_pipeline? }
@inside_txn
#=> true

## transaction_or_pipeline? is true inside a Familia pipeline
@inside_pipe = nil
Familia.pipelined { @inside_pipe = Familia.transaction_or_pipeline? }
@inside_pipe
#=> true

## assert_replies_available! returns nil outside any block
Familia.assert_replies_available!('Example#op')
#=> nil

## assert_replies_available! raises OperationModeError inside a transaction
@guard_error = nil
Familia.transaction do
  Familia.assert_replies_available!('Example#op')
rescue Familia::OperationModeError => e
  @guard_error = e
end
[@guard_error.class, @guard_error.message.start_with?('Example#op cannot run inside a transaction or pipeline')]
#=> [Familia::OperationModeError, true]

## assert_replies_available! raises OperationModeError inside a pipeline
@guard_error = nil
Familia.pipelined do
  Familia.assert_replies_available!('Example#op')
rescue Familia::OperationModeError => e
  @guard_error = e
end
@guard_error.class
#=> Familia::OperationModeError

# Teardown
Familia.dbclient.del(@test_key)
