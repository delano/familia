# try/integration/futures/hashkey_futures_try.rb
#
# frozen_string_literal: true

# HashKey methods inside transaction, atomic_write and pipelined blocks,
# where every command reply is a Redis::Future until the block completes.
#
# Policy (docs/reference/transaction_safety.md, "Command replies inside
# transactions and pipelines"):
#   - a method that only converts a reply returns the command's Future;
#   - a method that needs the reply to continue raises OperationModeError;
#   - a TTL refresh gated on a conditional write's reply is queued anyway.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Owner of the hashkey under test; its TTL makes hsetnx's refresh observable.
class FuturesHashOwner < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :ownerid
  field :ownerid
  field :name
  hashkey :counts
end

delete_test_dbkeys(FuturesHashOwner)

@owner = FuturesHashOwner.new(ownerid: 'fho-1', name: 'original')
@owner.save

# Seeds the hash with known contents before each testcase.
@reset = lambda do
  @owner.counts.delete!
  @owner.counts.update('views' => 5, 'label' => 'five', 'ratio' => 1.5)
end

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @owner.atomic_write do
    @owner.name = name
    captured = blk.call
  end
  [captured, FuturesHashOwner.load('fho-1').name]
end

# Runs the block inside a pipeline and returns its result.
@in_pipeline = lambda do |&blk|
  captured = nil
  @owner.pipelined { captured = blk.call }
  captured
end

## increment inside atomic_write returns a Future and persists both writes
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-incr') { @owner.counts.increment('views') }
[@ret.class, @ret.value, @persisted, @owner.counts['views']]
#=> [Redis::Future, 6, "aw-incr", 6]

## increment inside a pipeline returns a Future resolving to the Integer
@reset.call
@ret = @in_pipeline.call { @owner.counts.increment('views', 3) }
[@ret.class, @ret.value]
#=> [Redis::Future, 8]

## decrement inside atomic_write returns a Future and persists both writes
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-decr') { @owner.counts.decrement('views', 2) }
[@ret.value, @persisted, @owner.counts['views']]
#=> [3, "aw-decr", 3]

## decrement inside a pipeline returns a Future resolving to the Integer
@reset.call
@ret = @in_pipeline.call { @owner.counts.decr('views') }
[@ret.class, @ret.value]
#=> [Redis::Future, 4]

## incrbyfloat inside atomic_write returns a Future and persists both writes
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-float') { @owner.counts.incrbyfloat('ratio', 0.25) }
[@ret.value, @persisted, @owner.counts['ratio']]
#=> [1.75, "aw-float", 1.75]

## incrbyfloat inside a pipeline resolves to a Float (redis-rb's conversion)
@reset.call
@ret = @in_pipeline.call { @owner.counts.incrbyfloat('ratio', 1) }
[@ret.class, @ret.value.class, @ret.value]
#=> [Redis::Future, Float, 2.5]

## increment inside a transaction returns a Future
@reset.call
@ret = nil
@owner.transaction { @ret = @owner.counts.increment('views') }
[@ret.class, @owner.counts['views']]
#=> [Redis::Future, 6]

## several counter calls and a scalar write in one atomic_write all persist
@reset.call
@owner.atomic_write do
  @owner.name = 'aw-many'
  @owner.counts.increment('views')
  @owner.counts.incrbyfloat('ratio', 0.5)
  @owner.counts.decrement('views', 3)
end
[FuturesHashOwner.load('fho-1').name, @owner.counts['views'], @owner.counts['ratio']]
#=> ["aw-many", 3, 2.0]

## empty? inside atomic_write passes the HLEN Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-empty') { @owner.counts.empty? }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, 3, "aw-empty"]

## empty? inside a pipeline passes the HLEN Future through
@reset.call
@ret = @in_pipeline.call { @owner.counts.empty? }
[@ret.class, @ret.value]
#=> [Redis::Future, 3]

## values inside atomic_write passes the HVALS Future through (raw replies)
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-values') { @owner.counts.values }
[@ret.class, @ret.value.sort, @persisted]
#=> [Redis::Future, ["\"five\"", "1.5", "5"], "aw-values"]

## values inside a pipeline passes the HVALS Future through
@reset.call
@ret = @in_pipeline.call { @owner.counts.values }
@ret.class
#=> Redis::Future

## hgetall inside atomic_write passes the HGETALL Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-hgetall') { @owner.counts.hgetall }
[@ret.class, @ret.value['views'], @persisted]
#=> [Redis::Future, "5", "aw-hgetall"]

## hgetall inside a pipeline passes the HGETALL Future through
@reset.call
@ret = @in_pipeline.call { @owner.counts.all }
[@ret.class, @ret.value['label']]
#=> [Redis::Future, "\"five\""]

## values_at inside atomic_write passes the HMGET Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-values-at') { @owner.counts.values_at('views', 'label') }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, ["5", "\"five\""], "aw-values-at"]

## values_at inside a pipeline passes the HMGET Future through
@reset.call
@ret = @in_pipeline.call { @owner.counts.values_at('ratio') }
[@ret.class, @ret.value]
#=> [Redis::Future, ["1.5"]]

## scan inside atomic_write passes the HSCAN Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-scan') { @owner.counts.scan(0) }
[@ret.class, @ret.value.first, @persisted]
#=> [Redis::Future, "0", "aw-scan"]

## scan inside a pipeline passes the HSCAN Future through
@reset.call
@ret = @in_pipeline.call { @owner.counts.scan(0, match: 'view*') }
[@ret.class, @ret.value.last]
#=> [Redis::Future, [["views", "5"]]]

## randfield with values inside atomic_write passes the Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-rand') { @owner.counts.randfield(3, withvalues: true) }
[@ret.class, @ret.value.map(&:first).sort, @persisted]
#=> [Redis::Future, ["label", "ratio", "views"], "aw-rand"]

## randfield with values inside a pipeline passes the Future through
@reset.call
@ret = @in_pipeline.call { @owner.counts.randfield(1, withvalues: true) }
[@ret.class, @ret.value.size]
#=> [Redis::Future, 1]

## hsetnx inside atomic_write returns a Future and persists both writes
@owner.counts.delete!
@ret, @persisted = @in_atomic_write.call('aw-hsetnx') { @owner.counts.hsetnx('fresh', 1) }
[@ret.class, @ret.value, @persisted, @owner.counts['fresh']]
#=> [Redis::Future, true, "aw-hsetnx", 1]

## hsetnx inside a transaction queues the TTL refresh for the key it creates
@owner.counts.delete!
@ret = nil
@owner.transaction { @ret = @owner.counts.hsetnx('fresh', 1) }
[@ret.class, @owner.counts.ttl.positive?]
#=> [Redis::Future, true]

## hsetnx inside a pipeline queues the TTL refresh for the key it creates
@owner.counts.delete!
@ret = @in_pipeline.call { @owner.counts.hsetnx('fresh', 1) }
[@ret.class, @ret.value, @owner.counts.ttl.positive?]
#=> [Redis::Future, true, true]

## fetch inside atomic_write raises OperationModeError and persists nothing
@reset.call
@err = nil
begin
  @in_atomic_write.call('aw-fetch') { @owner.counts.fetch('missing', 0) }
rescue Familia::OperationModeError => e
  @err = e
end
[@err.class, FuturesHashOwner.load('fho-1').name == 'aw-fetch']
#=> [Familia::OperationModeError, false]

## fetch inside a pipeline raises OperationModeError
@err = nil
begin
  @in_pipeline.call { @owner.counts.fetch('views') }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.start_with?('HashKey#fetch cannot run inside a transaction or pipeline')
#=> true

## each inside atomic_write raises OperationModeError
@reset.call
@err = nil
begin
  @in_atomic_write.call('aw-each') { @owner.counts.each { |_f, _v| nil } }
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## each inside a pipeline raises OperationModeError
@err = nil
begin
  @in_pipeline.call { @owner.counts.each.to_a }
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## refresh! inside atomic_write raises OperationModeError
@err = nil
begin
  @in_atomic_write.call('aw-refresh') { @owner.counts.refresh! }
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## refresh inside a pipeline raises OperationModeError
@err = nil
begin
  @in_pipeline.call { @owner.counts.refresh }
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## outside a block: increment still returns an Integer
@reset.call
@owner.counts.increment('views')
#=> 6

## outside a block: incrbyfloat still returns a Float
@reset.call
@owner.counts.incrbyfloat('ratio', 0.5)
#=> 2.0

## outside a block: empty? still returns a Boolean
@reset.call
[@owner.counts.empty?, FuturesHashOwner.new(ownerid: 'fho-none').counts.empty?]
#=> [false, true]

## outside a block: values, hgetall and values_at still deserialize
@reset.call
[@owner.counts.values.sort_by(&:to_s), @owner.counts.hgetall['views'], @owner.counts.values_at('label', 'views')]
#=> [[1.5, 5, "five"], 5, ["five", 5]]

## outside a block: scan still returns an Integer cursor and deserialized values
@reset.call
@owner.counts.scan(0, match: 'views')
#=> [0, {"views"=>5}]

## outside a block: fetch still returns the value or the default
@reset.call
[@owner.counts.fetch('views'), @owner.counts.fetch('missing', :dflt)]
#=> [5, :dflt]

## outside a block: randfield with values returns deserialized [field, value] pairs
@reset.call
@owner.counts.randfield(3, withvalues: true).sort_by(&:first)
#=> [["label", "five"], ["ratio", 1.5], ["views", 5]]

## outside a block: hsetnx returns true for a new field and refreshes the TTL
@owner.counts.delete!
[@owner.counts.hsetnx('fresh', 1), @owner.counts.ttl.positive?]
#=> [true, true]

## outside a block: hsetnx returns false for an existing field
@owner.counts.hsetnx('fresh', 2)
#=> false

# Teardown
delete_test_dbkeys(FuturesHashOwner)
