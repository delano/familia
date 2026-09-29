# try/integration/futures/scalar_futures_try.rb
#
# frozen_string_literal: true

# StringKey, JsonStringKey, Counter and Lock methods inside transaction,
# atomic_write and pipelined blocks, where every command reply is a
# Redis::Future until the block completes. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Owner of one of each scalar DataType; its TTL makes setnx's refresh observable.
class FuturesScalarOwner < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :ownerid
  field :ownerid
  field :name
  string :nick
  json_string :prefs
  counter :hits
  lock :mutex
end

delete_test_dbkeys(FuturesScalarOwner)

@owner = FuturesScalarOwner.new(ownerid: 'fso-1', name: 'original')
@owner.save

@reset = lambda do
  @owner.nick.value = 'nickname'
  @owner.prefs.value = { 'theme' => 'dark', 'size' => 12 }
  @owner.hits.value = 3
  @owner.mutex.delete!
end

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @owner.atomic_write do
    @owner.name = name
    captured = blk.call
  end
  [captured, FuturesScalarOwner.load('fso-1').name]
end

@in_pipeline = lambda do |&blk|
  captured = nil
  @owner.pipelined { captured = blk.call }
  captured
end

## StringKey#char_count inside atomic_write passes the GET Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-size') { @owner.nick.size }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, "nickname", "aw-size"]

## StringKey#empty? inside a pipeline passes the GET Future through
@reset.call
@ret = @in_pipeline.call { @owner.nick.empty? }
[@ret.class, @ret.value]
#=> [Redis::Future, "nickname"]

## StringKey#to_s inside atomic_write passes the GET Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-to-s') { @owner.nick.to_s }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, "nickname", "aw-to-s"]

## StringKey#to_i inside a pipeline passes the GET Future through
@reset.call
@owner.nick.value = '42'
@ret = @in_pipeline.call { @owner.nick.to_i }
[@ret.class, @ret.value]
#=> [Redis::Future, "42"]

## JsonStringKey#char_count inside atomic_write passes the GET Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-json-size') { @owner.prefs.char_count }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, "{\"theme\":\"dark\",\"size\":12}", "aw-json-size"]

## JsonStringKey#empty? inside a pipeline passes the GET Future through
@reset.call
@ret = @in_pipeline.call { @owner.prefs.empty? }
@ret.class
#=> Redis::Future

## JsonStringKey#to_s, #to_i and #to_f inside atomic_write pass Futures through
@reset.call
@owner.prefs.value = 7
@ret, @persisted = @in_atomic_write.call('aw-json-conv') do
  [@owner.prefs.to_s, @owner.prefs.to_i, @owner.prefs.to_f]
end
[@ret.map(&:class), @ret.map(&:value), @persisted]
#=> [[Redis::Future, Redis::Future, Redis::Future], ["7", "7", "7"], "aw-json-conv"]

## JsonStringKey#to_i inside a pipeline passes the GET Future through
@reset.call
@owner.prefs.value = 8
@ret = @in_pipeline.call { @owner.prefs.to_i }
[@ret.class, @ret.value]
#=> [Redis::Future, "8"]

## JsonStringKey#setnx inside a pipeline queues the TTL refresh for a new key
@owner.prefs.delete!
@ret = @in_pipeline.call { @owner.prefs.setnx('first') }
[@ret.class, @ret.value, @owner.prefs.ttl.positive?]
#=> [Redis::Future, true, true]

## Counter#value inside atomic_write passes the GET Future through
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-counter') { @owner.hits.value }
[@ret.class, @ret.value, @persisted]
#=> [Redis::Future, "3", "aw-counter"]

## Counter#to_i inside a pipeline passes the GET Future through
@reset.call
@ret = @in_pipeline.call { @owner.hits.to_i }
[@ret.class, @ret.value]
#=> [Redis::Future, "3"]

## Counter#reset inside atomic_write passes the SET Future through and persists both
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-reset') { @owner.hits.reset(10) }
[@ret.class, @ret.value, @persisted, @owner.hits.value]
#=> [Redis::Future, "OK", "aw-reset", 10]

## Counter#reset inside a pipeline passes the SET Future through
@reset.call
@ret = @in_pipeline.call { @owner.hits.reset }
[@ret.class, @owner.hits.value]
#=> [Redis::Future, 0]

## Counter#increment and a scalar write in one atomic_write both persist
@reset.call
@ret, @persisted = @in_atomic_write.call('aw-incr') { @owner.hits.increment }
[@ret.value, @persisted, @owner.hits.value]
#=> [4, "aw-incr", 4]

## Counter#increment_if_less_than inside atomic_write raises and persists nothing
@reset.call
@err = nil
begin
  @in_atomic_write.call('aw-iflt') { @owner.hits.increment_if_less_than(10) }
rescue Familia::OperationModeError => e
  @err = e
end
[@err.class, FuturesScalarOwner.load('fso-1').name == 'aw-iflt', @owner.hits.value]
#=> [Familia::OperationModeError, false, 3]

## Counter#increment_if_less_than inside a pipeline raises OperationModeError
@err = nil
begin
  @in_pipeline.call { @owner.hits.increment_if_less_than(10) }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.start_with?('Counter#increment_if_less_than cannot run inside a transaction or pipeline')
#=> true

## Counter#increment_if_less_than inside a transaction raises OperationModeError
@err = nil
begin
  @owner.transaction { @owner.hits.increment_if_less_than(10) }
rescue Familia::OperationModeError => e
  @err = e
end
@err.class
#=> Familia::OperationModeError

## Lock#release inside atomic_write passes the EVAL Future through and releases
@reset.call
@owner.mutex.acquire('tok-1')
@ret, @persisted = @in_atomic_write.call('aw-release') { @owner.mutex.release('tok-1') }
[@ret.class, @ret.value, @persisted, @owner.mutex.locked?]
#=> [Redis::Future, 1, "aw-release", false]

## Lock#release by a non-owner inside a pipeline returns a Future that resolves to 0
# The Future itself is truthy; only its value after the block says whether
# the lock was released.
@reset.call
@owner.mutex.acquire('tok-2')
@ret = @in_pipeline.call { @owner.mutex.release('other') }
[@ret.class, @ret.value, @owner.mutex.held_by?('tok-2')]
#=> [Redis::Future, 0, true]

## Lock#locked? and #held_by? inside atomic_write raise and persist nothing
@reset.call
@owner.mutex.acquire('tok-3')
@name_before = FuturesScalarOwner.load('fso-1').name
@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end
[@refused.call { @in_atomic_write.call('aw-locked') { @owner.mutex.locked? } },
 @refused.call { @in_atomic_write.call('aw-held') { @owner.mutex.held_by?('tok-3') } },
 FuturesScalarOwner.load('fso-1').name == @name_before, @owner.mutex.held_by?('tok-3')]
#=> [Familia::OperationModeError, Familia::OperationModeError, true, true]

## Lock#held_by? by a non-owner inside a transaction raises instead of returning a truthy Future
@reset.call
@owner.mutex.acquire('owner-token')
@err = nil
begin
  @owner.transaction { @owner.mutex.held_by?('intruder') }
rescue Familia::OperationModeError => e
  @err = e
end
[@err.message.start_with?('Lock#held_by? cannot run inside a transaction or pipeline'),
 @owner.mutex.held_by?('owner-token')]
#=> [true, true]

## Lock#locked? inside a pipeline raises OperationModeError
@reset.call
@refused.call { @in_pipeline.call { @owner.mutex.locked? } }
#=> Familia::OperationModeError

## Lock#empty? on a held lock inside a transaction raises instead of returning a truthy Future
@reset.call
@owner.mutex.acquire('holder')
[@refused.call { @owner.transaction { @owner.mutex.empty? } }, @owner.mutex.held_by?('holder')]
#=> [Familia::OperationModeError, true]

## Lock#empty? inside a pipeline names itself in the error
@reset.call
@err = nil
begin
  @in_pipeline.call { @owner.mutex.empty? }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.start_with?('Lock#empty? cannot run inside a transaction or pipeline')
#=> true

## the generated predicate of a lock field inside atomic_write raises and persists nothing
@reset.call
@name_before = FuturesScalarOwner.load('fso-1').name
[@refused.call { @in_atomic_write.call('aw-mutex-pred') { @owner.mutex? } },
 FuturesScalarOwner.load('fso-1').name == @name_before]
#=> [Familia::OperationModeError, true]

## outside a block: StringKey conversions keep their return types
@reset.call
[@owner.nick.size, @owner.nick.empty?, @owner.nick.to_s, FuturesScalarOwner.new(ownerid: 'fso-none').nick.empty?]
#=> [8, false, "nickname", true]

## outside a block: StringKey#to_s falls back to the inspect-style string
FuturesScalarOwner.new(ownerid: 'fso-none').nick.to_s.start_with?('#<Familia::StringKey:0x')
#=> true

## outside a block: JsonStringKey conversions keep their return types
@reset.call
@owner.prefs.value = 7
[@owner.prefs.to_s, @owner.prefs.to_i, @owner.prefs.to_f, @owner.prefs.char_count, @owner.prefs.empty?]
#=> ["7", 7, 7.0, 1, false]

## outside a block: JsonStringKey conversions return nil for a missing key
@owner.prefs.delete!
[@owner.prefs.to_s, @owner.prefs.to_i, @owner.prefs.to_f, @owner.prefs.char_count]
#=> [nil, nil, nil, 0]

## outside a block: Counter keeps Integer values and Boolean reset
@reset.call
[@owner.hits.value, @owner.hits.to_i, @owner.hits.reset(5), @owner.hits.value]
#=> [3, 3, true, 5]

## outside a block: increment_if_less_than returns the new value or false
@reset.call
[@owner.hits.increment_if_less_than(4), @owner.hits.increment_if_less_than(4)]
#=> [4, false]

## outside a block: Lock predicates and release keep Boolean results
@reset.call
@owner.mutex.acquire('tok-4')
[@owner.mutex.locked?, @owner.mutex.held_by?('tok-4'), @owner.mutex.held_by?('x'),
 @owner.mutex.release('x'), @owner.mutex.release('tok-4'), @owner.mutex.locked?]
#=> [true, true, false, false, true, false]

## outside a block: Lock#empty? and the generated predicate keep Boolean results
@reset.call
@free = [@owner.mutex.empty?, @owner.mutex?]
@owner.mutex.acquire('tok-5')
[@free, [@owner.mutex.empty?, @owner.mutex?]]
#=> [[true, false], [false, true]]

# Teardown
delete_test_dbkeys(FuturesScalarOwner)
