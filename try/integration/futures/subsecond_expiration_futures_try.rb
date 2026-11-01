# try/integration/futures/subsecond_expiration_futures_try.rb
#
# frozen_string_literal: true

# Conditional writes (HashKey#hsetnx, JsonStringKey#setnx and #value with a
# default, ListKey#insert) under a positive default_expiration below one
# second. Outside a block #update_expiration skips the refresh only when the
# expiration is 0, so 0.5 reaches EXPIRE as 0 and the key just written is
# deleted. Inside a transaction or pipeline the queued EVAL makes the same
# decision, so the key ends in the same state: gone, TTL -2. A write that
# does nothing still leaves an existing key alone, and a 0 default still
# sends no EXPIRE at all.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Owner whose default TTL rounds down to 0 seconds.
class FuturesSubsecondOwner < Familia::Horreum
  feature :expiration
  default_expiration 0.5
  identifier_field :ownerid
  field :ownerid
  hashkey :attrs
  hashkey :sticky, no_expiration: true
  list :items
  json_string :settings, default: { 'theme' => 'light' }
end

# Owner with no default TTL at all.
class FuturesUnexpiringOwner < Familia::Horreum
  feature :expiration
  default_expiration 0
  identifier_field :ownerid
  field :ownerid
  hashkey :attrs
end

delete_test_dbkeys(FuturesSubsecondOwner, FuturesUnexpiringOwner)

@owner = FuturesSubsecondOwner.new(ownerid: 'fso-1')
@unexpiring = FuturesUnexpiringOwner.new(ownerid: 'fuo-1')

# Runs the block inside a pipeline and returns its result.
@in_pipeline = lambda do |&blk|
  captured = nil
  @owner.pipelined { captured = blk.call }
  captured
end

# Seeds an existing hash or list with an hour to live. Written with raw
# commands: every DataType mutator refreshes the TTL, which under this
# owner's default would delete the key again.
@seed_hash = lambda do
  @owner.attrs.delete!
  @owner.attrs.dbclient.hset(@owner.attrs.dbkey, 'views', '5')
  @owner.attrs.expire(3600)
end

@seed_list = lambda do
  @owner.items.delete!
  @owner.items.dbclient.rpush(@owner.items.dbkey, '"a"')
  @owner.items.expire(3600)
end

## the owner's relations inherit the sub-second default
[@owner.attrs.default_expiration, @owner.settings.default_expiration, @owner.items.default_expiration]
#=> [0.5, 0.5, 0.5]

## outside a block: hsetnx refreshes with EXPIRE 0, which deletes the new hash
@owner.attrs.delete!
[@owner.attrs.hsetnx('fresh', 1), @owner.attrs.ttl]
#=> [true, -2]

## hsetnx inside a transaction leaves the new hash in the same state as outside a block
@owner.attrs.delete!
@ret = nil
@owner.transaction { @ret = @owner.attrs.hsetnx('fresh', 1) }
[@ret.class, @ret.value, @owner.attrs.ttl]
#=> [Redis::Future, true, -2]

## hsetnx inside a pipeline leaves the new hash in the same state as outside a block
@owner.attrs.delete!
@ret = @in_pipeline.call { @owner.attrs.hsetnx('fresh', 1) }
[@ret.value, @owner.attrs.ttl]
#=> [true, -2]

## hsetnx on an existing field inside a transaction still leaves the hash and its TTL alone
@seed_hash.call
@ret = nil
@owner.transaction { @ret = @owner.attrs.hsetnx('views', 9) }
[@ret.value, @owner.attrs['views'], @owner.attrs.ttl > 100]
#=> [false, 5, true]

## outside a block: a json_string read with a default creates the key and EXPIRE 0 deletes it
@owner.settings.delete!
[@owner.settings.value, @owner.settings.ttl]
#=> [{"theme"=>"light"}, -2]

## a json_string read with a default inside a transaction leaves the key in the same state
@owner.settings.delete!
@owner.transaction { @owner.settings.value }
@owner.settings.ttl
#=> -2

## JsonStringKey#setnx inside a pipeline leaves the new key in the same state as outside a block
@owner.settings.delete!
@ret = @in_pipeline.call { @owner.settings.setnx({ 'theme' => 'dark' }) }
[@ret.value, @owner.settings.ttl]
#=> [true, -2]

## outside a block: insert that finds its pivot refreshes with EXPIRE 0, which deletes the list
@seed_list.call
[@owner.items.insert(:before, 'a', 'b'), @owner.items.ttl]
#=> [2, -2]

## insert that finds its pivot inside a transaction leaves the list in the same state
@seed_list.call
@ret = nil
@owner.transaction { @ret = @owner.items.insert(:before, 'a', 'b') }
[@ret.value, @owner.items.ttl]
#=> [2, -2]

## insert with a missing pivot inside a pipeline still leaves the list and its TTL alone
@seed_list.call
@ret = @in_pipeline.call { @owner.items.insert(:after, 'missing', 'x') }
[@ret.value, @owner.items.to_a, @owner.items.ttl > 100]
#=> [-1, ["a"], true]

## hsetnx inside a transaction on a no_expiration hashkey of the same owner sends no EXPIRE
@owner.sticky.delete!
@ret = nil
@owner.transaction { @ret = @owner.sticky.hsetnx('fresh', 1) }
[@ret.value, @owner.sticky['fresh'], @owner.sticky.ttl]
#=> [true, 1, -1]

## hsetnx inside a pipeline under a zero class default sends no EXPIRE
@unexpiring.attrs.delete!
@ret = nil
@unexpiring.pipelined { @ret = @unexpiring.attrs.hsetnx('fresh', 1) }
[@ret.value, @unexpiring.attrs['fresh'], @unexpiring.attrs.ttl]
#=> [true, 1, -1]

# Teardown
delete_test_dbkeys(FuturesSubsecondOwner, FuturesUnexpiringOwner)
