# try/integration/futures/sorted_set_futures_try.rb
#
# frozen_string_literal: true

# SortedSet methods inside transaction, atomic_write and pipelined blocks,
# where every command reply is a Redis::Future until the block completes.
# See docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Owner of the sorted set under test; its TTL makes the pop refresh observable.
class FuturesZsetOwner < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :ownerid
  field :ownerid
  field :name
  zset :scores
end

delete_test_dbkeys(FuturesZsetOwner)

@owner = FuturesZsetOwner.new(ownerid: 'fzo-1', name: 'original')
@owner.save
@other = Familia::SortedSet.new('futures_zset_other')

@reset = lambda do
  @owner.scores.delete!
  @owner.scores.update('a' => 1, 'b' => 2, 'c' => 3)
  @other.delete!
  @other.update('b' => 20, 'd' => 40)
end

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @owner.atomic_write do
    @owner.name = name
    captured = blk.call
  end
  [captured, FuturesZsetOwner.load('fzo-1').name]
end

@in_pipeline = lambda do |&blk|
  captured = nil
  @owner.pipelined { captured = blk.call }
  captured
end

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## empty? inside atomic_write passes the ZCARD Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-empty') { @owner.scores.empty? }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, 3, "aw-empty"]

## empty? inside a pipeline passes the ZCARD Future through
@reset.call
@ret = @in_pipeline.call { @owner.scores.empty? }
[@ret.class, @ret.value]
#=> [Redis::Future, 3]

## score, member?, rank and revrank inside atomic_write pass Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-score') do
  [@owner.scores.score('b'), @owner.scores.member?('b'), @owner.scores.rank('b'), @owner.scores.revrank('b')]
end
[@ret.map(&:class).uniq, @ret.map(&:value), @persisted]
#=> [[Redis::Future], [2.0, 1, 1, 1], "aw-score"]

## score and member? inside a pipeline pass Futures through
@reset.call
@ret = @in_pipeline.call { [@owner.scores['c'], @owner.scores.include?('zz')] }
[@ret.map(&:class).uniq, @ret.map(&:value)]
#=> [[Redis::Future], [3.0, nil]]

## members, revmembers and the range readers inside atomic_write pass Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-range') do
  [
    @owner.scores.members, @owner.scores.revmembers, @owner.scores.range(0, 0),
    @owner.scores.revrange(0, 0), @owner.scores.rangebyscore(2, 3), @owner.scores.revrangebyscore(3, 2),
    @owner.scores.rangebylex('-', '+'), @owner.scores.revrangebylex('+', '-'), @owner.scores.to_a
  ]
end
[@ret.map(&:class).uniq, @ret.map { |fut| fut.value.size }, @persisted]
#=> [[Redis::Future], [3, 3, 1, 1, 2, 2, 3, 3, 3], "aw-range"]

## members and range inside a pipeline pass Futures through
@reset.call
@ret = @in_pipeline.call { [@owner.scores.all, @owner.scores.range(0, -1)] }
[@ret.map(&:class).uniq, @ret.first.value]
#=> [[Redis::Future], ["\"a\"", "\"b\"", "\"c\""]]

## at, first and last inside atomic_write pass ZRANGE Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-at') { [@owner.scores.at(1), @owner.scores.first, @owner.scores.last] }
[@ret.map(&:class).uniq, @ret.map(&:value), @persisted]
#=> [[Redis::Future], [["\"b\""], ["\"a\""], ["\"c\""]], "aw-at"]

## first inside a pipeline passes the ZRANGE Future through
@reset.call
@ret = @in_pipeline.call { @owner.scores.first }
[@ret.class, @ret.value]
#=> [Redis::Future, ["\"a\""]]

## popmin inside atomic_write passes the Future through and persists both writes
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-popmin') { @owner.scores.popmin }
[@ret.class, @ret.value, @persisted, @owner.scores.members]
#=> [Redis::Future, ["\"a\"", 1.0], "aw-popmin", ["b", "c"]]

## popmax with a count inside a pipeline queues the TTL refresh with the pop
@reset.call
@owner.scores.expire(100)
@ret = @in_pipeline.call { @owner.scores.popmax(2) }
[@ret.class, @ret.value, @owner.scores.ttl > 100]
#=> [Redis::Future, [["\"c\"", 3.0], ["\"b\"", 2.0]], true]

## mscore inside atomic_write passes the Future through (Floats from redis-rb)
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-mscore') { @owner.scores.mscore('a', 'zz', 'c') }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, [1.0, nil, 3.0], "aw-mscore"]

## mscore inside a pipeline passes the Future through
@reset.call
@ret = @in_pipeline.call { @owner.scores.mscore('b') }
[@ret.class, @ret.value]
#=> [Redis::Future, [2.0]]

## union, inter and diff inside atomic_write pass Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-setops') do
  [@owner.scores.union(@other), @owner.scores.inter(@other, withscores: true), @owner.scores.diff(@other)]
end
[@ret.map(&:class).uniq, @ret[1].value, @persisted]
#=> [[Redis::Future], [["\"b\"", 22.0]], "aw-setops"]

## union with scores inside a pipeline passes the Future through
@reset.call
@ret = @in_pipeline.call { @owner.scores.union(@other, withscores: true) }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 4]

## randmember inside atomic_write passes the Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-rand') do
  [@owner.scores.randmember, @owner.scores.randmember(3), @owner.scores.randmember(3, withscores: true)]
end
[@ret.map(&:class).uniq, @ret[1].value.sort, @ret[2].value.map(&:last).sort, @persisted]
#=> [[Redis::Future], ["\"a\"", "\"b\"", "\"c\""], [1.0, 2.0, 3.0], "aw-rand"]

## randmember inside a pipeline passes the Future through
@reset.call
@ret = @in_pipeline.call { @owner.scores.randmember(2) }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 2]

## scan inside atomic_write passes the ZSCAN Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-scan') { @owner.scores.scan(0) }
[@ret.class, @ret.value.first, @persisted]
#=> [Redis::Future, "0", "aw-scan"]

## scan inside a pipeline passes the ZSCAN Future through
@reset.call
@ret = @in_pipeline.call { @owner.scores.scan(0) }
[@ret.class, @ret.value.last.size]
#=> [Redis::Future, 3]

## increment inside atomic_write returns a Future resolving to a Float
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-incr') { @owner.scores.increment('a', 5) }
[@ret.class, @ret.value, @persisted, @owner.scores.score('a')]
#=> [Redis::Future, 6.0, "aw-incr", 6.0]

## decrement inside a pipeline returns a Future resolving to a Float
@reset.call
@ret = @in_pipeline.call { @owner.scores.decrement('c') }
[@ret.class, @ret.value]
#=> [Redis::Future, 2.0]

## each inside atomic_write raises OperationModeError and persists nothing
@reset.call
@err_class = @refused.call { @in_atomic_write.call('aw-each') { @owner.scores.each { |_m| nil } } }
[@err_class, FuturesZsetOwner.load('fzo-1').name == 'aw-each']
#=> [Familia::OperationModeError, false]

## each with a score range inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { @owner.scores.each(since: 0) { |_m| nil } } }
#=> Familia::OperationModeError

## the raw iterators inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.scores.eachraw { |_e| nil } } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.scores.eachraw_with_index { |_e, _i| nil } } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.scores.collectraw(&:upcase) } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.scores.selectraw { |_e| true } } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError]

## the raw iterators inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { @owner.scores.eachraw { |_e| nil } } },
  @refused.call { @in_pipeline.call { @owner.scores.eachraw_with_index { |_e, _i| nil } } },
  @refused.call { @in_pipeline.call { @owner.scores.collectraw(&:upcase) } },
  @refused.call { @in_pipeline.call { @owner.scores.selectraw { |_e| true } } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError]

## outside a block: predicates, scores and ranks keep their return types
@reset.call
[@owner.scores.empty?, @owner.scores.score('b'), @owner.scores.score('zz'), @owner.scores.member?('a'),
 @owner.scores.member?('zz'), @owner.scores.rank('c'), @owner.scores.revrank('c'), @owner.scores.rank('zz')]
#=> [false, 2.0, nil, true, false, 2, 0, nil]

## outside a block: range readers and at still deserialize
@reset.call
[@owner.scores.members, @owner.scores.revrange(0, 0), @owner.scores.rangebyscore(2, 3), @owner.scores.at(1),
 @owner.scores.last, @owner.scores.rangebylex('-', '+')]
#=> [["a", "b", "c"], ["c"], ["b", "c"], "b", "c", ["a", "b", "c"]]

## outside a block: popmin and popmax return deserialized pairs with Float scores
@reset.call
[@owner.scores.popmin, @owner.scores.popmax(2), @owner.scores.popmin]
#=> [["a", 1.0], [["c", 3.0], ["b", 2.0]], nil]

## outside a block: mscore and set operations keep their shapes
@reset.call
[@owner.scores.mscore('a', 'zz'), @owner.scores.inter(@other, withscores: true), @owner.scores.diff(@other).sort]
#=> [[1.0, nil], [["b", 22.0]], ["a", "c"]]

## outside a block: randmember and scan pair deserialized members with Float scores
@reset.call
[@owner.scores.randmember(3, withscores: true).sort, @owner.scores.scan(0)]
#=> [[["a", 1.0], ["b", 2.0], ["c", 3.0]], [0, [["a", 1.0], ["b", 2.0], ["c", 3.0]]]]

## outside a block: increment still returns a Float and iterators still iterate
@reset.call
[@owner.scores.increment('a', 2), @owner.scores.each.to_a.sort, @owner.scores.collectraw(&:size)]
#=> [3.0, ["a", "b", "c"], [3, 3, 3]]

# Teardown
@other.delete!
delete_test_dbkeys(FuturesZsetOwner)
