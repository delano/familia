# try/features/atomic_counter_try.rb
#
# frozen_string_literal: true

# Tests for Counter#increment_if_less_than atomic Lua implementation.
#
# The method was changed from a non-atomic GET+INCRBY pair to an atomic
# Lua EVAL so that concurrent callers cannot exceed the threshold. These
# tests verify both the functional contract and the atomicity guarantee.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class AtomicCounterModel < Familia::Horreum
  identifier_field :name
  field :name
  counter :hit_count
end

@obj = AtomicCounterModel.new(name: "atomic-test-#{$$}")
@obj.save
@thread_count = 20
@threshold = 10

## Basic increment below threshold returns new value as Integer
@obj.hit_count.reset(0)
result = @obj.hit_count.increment_if_less_than(5)
[result, result.is_a?(Integer)]
#=> [1, true]

## Successive increments return cumulative value
@obj.hit_count.reset(0)
@obj.hit_count.increment_if_less_than(5)
@obj.hit_count.increment_if_less_than(5)
result = @obj.hit_count.increment_if_less_than(5)
result
#=> 3

## Returns false when counter equals threshold
@obj.hit_count.reset(5)
@obj.hit_count.increment_if_less_than(5)
#=> false

## Returns false when counter exceeds threshold
@obj.hit_count.reset(10)
@obj.hit_count.increment_if_less_than(5)
#=> false

## Custom amount increments by specified value
@obj.hit_count.reset(0)
result = @obj.hit_count.increment_if_less_than(10, 3)
result
#=> 3

## Custom amount returns new cumulative value
@obj.hit_count.reset(0)
@obj.hit_count.increment_if_less_than(10, 3)
result = @obj.hit_count.increment_if_less_than(10, 3)
result
#=> 6

## Threshold boundary: last increment succeeds at threshold minus one
@obj.hit_count.reset(0)
4.times { @obj.hit_count.increment_if_less_than(5) }
result = @obj.hit_count.increment_if_less_than(5)
[result, @obj.hit_count.to_i]
#=> [5, 5]

## Threshold boundary: next increment after reaching threshold returns false
@obj.hit_count.reset(0)
5.times { @obj.hit_count.increment_if_less_than(5) }
@obj.hit_count.increment_if_less_than(5)
#=> false

## Counter value stays at threshold after failed increment
@obj.hit_count.reset(0)
5.times { @obj.hit_count.increment_if_less_than(5) }
@obj.hit_count.increment_if_less_than(5)
@obj.hit_count.to_i
#=> 5

## Atomicity: concurrent threads cannot exceed threshold
@obj.hit_count.reset(0)
barrier = Concurrent::CyclicBarrier.new(@thread_count)
results = Concurrent::Array.new

threads = @thread_count.times.map do
  Thread.new do
    barrier.wait
    @threshold.times do
      result = @obj.hit_count.increment_if_less_than(@threshold)
      results << result
    end
  end
end

threads.each(&:join)

final_value = @obj.hit_count.to_i
successes = results.count { |r| r != false }
failures = results.count { |r| r == false }

# The counter must never exceed the threshold. With the old non-atomic
# GET+INCRBY, concurrent threads could read the same "current" value
# before either incremented, causing the counter to overshoot.
[final_value, final_value <= @threshold, successes, successes + failures]
#=> [10, true, 10, 200]

## Atomicity: all successful increments return sequential values up to threshold
@obj.hit_count.reset(0)
barrier2 = Concurrent::CyclicBarrier.new(@thread_count)
values = Concurrent::Array.new

threads2 = @thread_count.times.map do
  Thread.new do
    barrier2.wait
    @threshold.times do
      result = @obj.hit_count.increment_if_less_than(@threshold)
      values << result if result != false
    end
  end
end

threads2.each(&:join)

sorted = values.sort
# Each successful increment returns a unique value from 1..threshold
[sorted, sorted == (1..@threshold).to_a]
#=> [[1, 2, 3, 4, 5, 6, 7, 8, 9, 10], true]

# Cleanup
@obj.hit_count.delete!
@obj.destroy!
