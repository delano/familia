# try/integration/futures/listkey_futures_try.rb
#
# frozen_string_literal: true

# ListKey methods inside transaction, atomic_write and pipelined blocks,
# where every command reply is a Redis::Future until the block completes.
# See docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Owner of the list under test; its TTL makes the gated refreshes observable.
class FuturesListOwner < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :ownerid
  field :ownerid
  field :name
  list :events
end

delete_test_dbkeys(FuturesListOwner)

@owner = FuturesListOwner.new(ownerid: 'flo-1', name: 'original')
@owner.save

@reset = lambda do
  @owner.events.delete!
  @owner.events.push('a', 'b', 'c', 'd')
end

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @owner.atomic_write do
    @owner.name = name
    captured = blk.call
  end
  [captured, FuturesListOwner.load('flo-1').name]
end

@in_pipeline = lambda do |&blk|
  captured = nil
  @owner.pipelined { captured = blk.call }
  captured
end

# Expects the block to raise Familia::OperationModeError and returns the
# error class (or whatever was raised instead).
@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## empty? inside atomic_write passes the LLEN Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-empty') { @owner.events.empty? }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, 4, "aw-empty"]

## empty? inside a pipeline passes the LLEN Future through
@reset.call
@ret = @in_pipeline.call { @owner.events.empty? }
[@ret.class, @ret.value]
#=> [Redis::Future, 4]

## pop with a count inside atomic_write passes the Future through and persists both
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-pop') { @owner.events.pop(2) }
[@ret.class, @ret.value, @persisted, @owner.events.members]
#=> [Redis::Future, ["\"d\"", "\"c\""], "aw-pop", ["a", "b"]]

## pop with a count inside a pipeline passes the Future through
@reset.call
@ret = @in_pipeline.call { @owner.events.pop(1) }
[@ret.class, @ret.value]
#=> [Redis::Future, ["\"d\""]]

## shift with a count inside atomic_write passes the Future through and persists both
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-shift') { @owner.events.shift(2) }
[@ret.class, @ret.value, @persisted, @owner.events.members]
#=> [Redis::Future, ["\"a\"", "\"b\""], "aw-shift", ["c", "d"]]

## shift with a count inside a pipeline passes the Future through
@reset.call
@ret = @in_pipeline.call { @owner.events.shift(3) }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 3]

## member? inside atomic_write passes the LPOS Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-member') { @owner.events.member?('c') }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, 2, "aw-member"]

## member? inside a pipeline passes the LPOS Future through
@reset.call
@ret = @in_pipeline.call { @owner.events.member?('zz') }
[@ret.class, @ret.value]
#=> [Redis::Future, nil]

## range, members and slices inside atomic_write pass LRANGE Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-range') do
  [@owner.events.range(0, 1), @owner.events.members, @owner.events[1..2], @owner.events[0, 2]]
end
[@ret.map(&:class).uniq, @ret.first.value, @ret[2].value, @persisted]
#=> [[Redis::Future], ["\"a\"", "\"b\""], ["\"b\"", "\"c\""], "aw-range"]

## to_a and Array() inside a pipeline raise OperationModeError
[@refused.call { @in_pipeline.call { @owner.events.to_a } },
 @refused.call { @in_pipeline.call { Array(@owner.events) } }]
#=> [Familia::OperationModeError, Familia::OperationModeError]

## range and members inside a pipeline pass LRANGE Futures through
@reset.call
@ret = @in_pipeline.call { [@owner.events.range, @owner.events.all] }
[@ret.map(&:class).uniq, @ret.last.value.size]
#=> [[Redis::Future], 4]

## insert inside atomic_write returns a Future and persists both writes
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-insert') { @owner.events.insert(:after, 'a', 'a2') }
[@ret.value, @persisted, @owner.events.members]
#=> [5, "aw-insert", ["a", "a2", "b", "c", "d"]]

## insert inside a pipeline queues the TTL refresh with the write
@reset.call
@owner.events.expire(100)
@ret = @in_pipeline.call { @owner.events.insert(:before, 'a', 'z') }
[@ret.value, @owner.events.ttl > 100]
#=> [5, true]

## pushx inside a pipeline queues the TTL refresh with the write
@reset.call
@owner.events.expire(100)
@ret = @in_pipeline.call { @owner.events.pushx('e') }
[@ret.value, @owner.events.ttl > 100]
#=> [5, true]

## unshiftx inside atomic_write returns a Future and persists both writes
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-unshiftx') { @owner.events.unshiftx('first') }
[@ret.value, @persisted, @owner.events.first]
#=> [5, "aw-unshiftx", "first"]

## unshiftx inside a pipeline on a missing list leaves it missing
@owner.events.delete!
@ret = @in_pipeline.call { @owner.events.unshiftx('first') }
[@ret.value, @owner.events.exists?]
#=> [0, false]

## each inside atomic_write raises OperationModeError and persists nothing
@reset.call
@err_class = @refused.call { @in_atomic_write.call('aw-each') { @owner.events.each { |_e| nil } } }
[@err_class, FuturesListOwner.load('flo-1').name == 'aw-each']
#=> [Familia::OperationModeError, false]

## each inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { @owner.events.each.to_a } }
#=> Familia::OperationModeError

## the raw iterators inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.events.eachraw { |_e| nil } } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.events.eachraw_with_index { |_e, _i| nil } } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.events.collectraw(&:upcase) } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.events.selectraw { |_e| true } } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError]

## the raw iterators inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { @owner.events.eachraw { |_e| nil } } },
  @refused.call { @in_pipeline.call { @owner.events.eachraw_with_index { |_e, _i| nil } } },
  @refused.call { @in_pipeline.call { @owner.events.collectraw(&:upcase) } },
  @refused.call { @in_pipeline.call { @owner.events.selectraw { |_e| true } } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError]

## outside a block: empty?, member? and pop/shift keep their return types
@reset.call
[@owner.events.empty?, @owner.events.member?('b'), @owner.events.member?('zz'),
 @owner.events.pop(1), @owner.events.shift(2)]
#=> [false, true, false, ["d"], ["a", "b"]]

## outside a block: pop with a count on a missing list returns nil
@owner.events.delete!
@owner.events.pop(2)
#=> nil

## outside a block: range, slices and iterators still deserialize
@reset.call
[@owner.events.range(1, 2), @owner.events[0, 2], @owner.events.each.to_a, @owner.events.collectraw(&:upcase)]
#=> [["b", "c"], ["a", "b"], ["a", "b", "c", "d"], ["\"A\"", "\"B\"", "\"C\"", "\"D\""]]

## outside a block: to_a still returns the deserialized elements
@reset.call
[@owner.events.to_a, @owner.events.to_a(2), Array(@owner.events)]
#=> [["a", "b", "c", "d"], ["a", "b"], ["a", "b", "c", "d"]]

## outside a block: insert and pushx refresh the TTL after a write
@reset.call
@owner.events.expire(100)
[@owner.events.insert(:after, 'd', 'e'), @owner.events.pushx('f'), @owner.events.ttl > 100]
#=> [5, 6, true]

# Teardown
delete_test_dbkeys(FuturesListOwner)
