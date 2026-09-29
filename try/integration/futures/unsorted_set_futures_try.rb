# try/integration/futures/unsorted_set_futures_try.rb
#
# frozen_string_literal: true

# UnsortedSet methods inside transaction, atomic_write and pipelined
# blocks, where every command reply is a Redis::Future until the block
# completes. See docs/reference/transaction_safety.md for the policy these
# tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Owner of the set under test.
class FuturesSetOwner < Familia::Horreum
  identifier_field :ownerid
  field :ownerid
  field :name
  set :tags
end

delete_test_dbkeys(FuturesSetOwner)

@owner = FuturesSetOwner.new(ownerid: 'fso-1', name: 'original')
@owner.save
@other = Familia::UnsortedSet.new('futures_set_other')

@reset = lambda do
  @owner.tags.delete!
  @owner.tags.add('a', 'b', 'c')
  @other.delete!
  @other.add('b', 'd')
end

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @owner.atomic_write do
    @owner.name = name
    captured = blk.call
  end
  [captured, FuturesSetOwner.load('fso-1').name]
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

## empty? inside atomic_write passes the SCARD Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-empty') { @owner.tags.empty? }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, 3, "aw-empty"]

## empty? inside a pipeline passes the SCARD Future through
@reset.call
@ret = @in_pipeline.call { @owner.tags.empty? }
[@ret.class, @ret.value]
#=> [Redis::Future, 3]

## members and all inside atomic_write pass SMEMBERS Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-members') { [@owner.tags.members, @owner.tags.all] }
[@ret.map(&:class).uniq, @ret.first.value.sort, @persisted]
#=> [[Redis::Future], ["\"a\"", "\"b\"", "\"c\""], "aw-members"]

## to_a, splat and JSON conversion inside atomic_write raise and persist nothing
# Conversion methods must return their type, so they refuse rather than
# hand back a Redis::Future.
@reset.call
@name_before = FuturesSetOwner.load('fso-1').name
[@refused.call { @in_atomic_write.call('aw-to-a') { @owner.tags.to_a } },
 @refused.call { @in_atomic_write.call('aw-splat') { [*@owner.tags] } },
 @refused.call { @in_atomic_write.call('aw-json') { @owner.tags.to_json } },
 FuturesSetOwner.load('fso-1').name == @name_before]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, true]

## members inside a pipeline passes the SMEMBERS Future through
@reset.call
@ret = @in_pipeline.call { @owner.tags.members }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 3]

## intersection, union and difference inside atomic_write pass Futures through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-setops') do
  [@owner.tags.intersection(@other), @owner.tags.union(@other), @owner.tags.difference(@other)]
end
[@ret.map(&:class).uniq, @ret.first.value, @ret.map { |fut| fut.value.size }, @persisted]
#=> [[Redis::Future], ["\"b\""], [1, 4, 2], "aw-setops"]

## union inside a pipeline passes the SUNION Future through
@reset.call
@ret = @in_pipeline.call { @owner.tags.union(@other) }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 4]

## scan inside atomic_write passes the SSCAN Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-scan') { @owner.tags.scan(0) }
[@ret.class, @ret.value.first, @persisted]
#=> [Redis::Future, "0", "aw-scan"]

## scan inside a pipeline passes the SSCAN Future through
@reset.call
@ret = @in_pipeline.call { @owner.tags.scan(0, match: '*a*') }
[@ret.class, @ret.value.last]
#=> [Redis::Future, ["\"a\""]]

## sample inside atomic_write passes the SRANDMEMBER Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-sample') { @owner.tags.sample(3) }
[@ret.class, @ret.value.sort, @persisted]
#=> [Redis::Future, ["\"a\"", "\"b\"", "\"c\""], "aw-sample"]

## sample inside a pipeline passes the SRANDMEMBER Future through
@reset.call
@ret = @in_pipeline.call { @owner.tags.random }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 1]

## add and remove with a scalar write in one atomic_write all persist
@reset.call
@owner.atomic_write do
  @owner.name = 'aw-writes'
  @owner.tags.add('z')
  @owner.tags.remove('a')
end
[FuturesSetOwner.load('fso-1').name, @owner.tags.members.sort]
#=> ["aw-writes", ["b", "c", "z"]]

## each inside atomic_write raises OperationModeError and persists nothing
@reset.call
@err_class = @refused.call { @in_atomic_write.call('aw-each') { @owner.tags.each { |_m| nil } } }
[@err_class, FuturesSetOwner.load('fso-1').name == 'aw-each']
#=> [Familia::OperationModeError, false]

## each inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { @owner.tags.each.to_a } }
#=> Familia::OperationModeError

## the raw iterators inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.tags.eachraw { |_e| nil } } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.tags.eachraw_with_index { |_e, _i| nil } } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.tags.collectraw(&:upcase) } },
  @refused.call { @in_atomic_write.call('aw-raw') { @owner.tags.selectraw { |_e| true } } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError]

## the raw iterators inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { @owner.tags.eachraw { |_e| nil } } },
  @refused.call { @in_pipeline.call { @owner.tags.eachraw_with_index { |_e, _i| nil } } },
  @refused.call { @in_pipeline.call { @owner.tags.collectraw(&:upcase) } },
  @refused.call { @in_pipeline.call { @owner.tags.selectraw { |_e| true } } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError]

## outside a block: empty? and the readers keep their return types
@reset.call
[@owner.tags.empty?, @owner.tags.members.sort, @owner.tags.intersection(@other), @owner.tags.difference(@other).sort]
#=> [false, ["a", "b", "c"], ["b"], ["a", "c"]]

## outside a block: to_a and splat still return the deserialized members
@reset.call
[@owner.tags.to_a.sort, [*@owner.tags].sort]
#=> [["a", "b", "c"], ["a", "b", "c"]]

## outside a block: scan, sample and the iterators still deserialize
@reset.call
[@owner.tags.scan(0).first, @owner.tags.scan(0).last.sort, @owner.tags.sample(3).sort, @owner.tags.each.to_a.sort]
#=> [0, ["a", "b", "c"], ["a", "b", "c"], ["a", "b", "c"]]

# Teardown
@other.delete!
delete_test_dbkeys(FuturesSetOwner)
