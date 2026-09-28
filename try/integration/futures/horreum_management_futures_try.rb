# try/integration/futures/horreum_management_futures_try.rb
#
# frozen_string_literal: true

# Horreum class-level finders, loaders and counters inside transaction,
# atomic_write and pipelined blocks, where every command reply is a
# Redis::Future until the block completes. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Plain record class: no indexes, so only the finder paths are exercised.
class FuturesMgmtRecord < Familia::Horreum
  identifier_field :recid
  field :recid
  field :name
end

delete_test_dbkeys(FuturesMgmtRecord)

FuturesMgmtRecord.new(recid: 'fmr-1', name: 'one').save
FuturesMgmtRecord.new(recid: 'fmr-2', name: 'two').save
@rec = FuturesMgmtRecord.load('fmr-1')
@key2 = 'futures_mgmt_record:fmr-2:object'

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @rec.atomic_write do
    @rec.name = name
    captured = blk.call
  end
  [captured, FuturesMgmtRecord.load('fmr-1').name]
end

@in_pipeline = lambda do |&blk|
  captured = nil
  FuturesMgmtRecord.pipelined { captured = blk.call }
  captured
end

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## finders inside atomic_write raise OperationModeError and persist nothing
@results = [
  @refused.call { @in_atomic_write.call('aw-find') { FuturesMgmtRecord.find_by_id('fmr-2') } },
  @refused.call { @in_atomic_write.call('aw-find') { FuturesMgmtRecord.load('fmr-2') } },
  @refused.call { @in_atomic_write.call('aw-find') { FuturesMgmtRecord.find_by_dbkey(@key2) } },
  @refused.call do
    @in_atomic_write.call('aw-find') { FuturesMgmtRecord.find_by_identifier('fmr-2', check_exists: false) }
  end,
]
[@results.uniq, FuturesMgmtRecord.load('fmr-1').name]
#=> [[Familia::OperationModeError], "one"]

## finders inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.find('fmr-2') } },
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.find_by_key('futures_mgmt_record:fmr-2:object') } },
].uniq
#=> [Familia::OperationModeError]

## loaders and full scans inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-load') { FuturesMgmtRecord.load_multi(%w[fmr-1 fmr-2]) } },
  @refused.call { @in_atomic_write.call('aw-load') { FuturesMgmtRecord.load_multi_by_keys([@key2]) } },
  @refused.call { @in_atomic_write.call('aw-load') { FuturesMgmtRecord.all } },
  @refused.call { @in_atomic_write.call('aw-load') { FuturesMgmtRecord.scan_count } },
  @refused.call { @in_atomic_write.call('aw-load') { FuturesMgmtRecord.scan_any? } },
].uniq
#=> [Familia::OperationModeError]

## loaders and full scans inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.load_batch(%w[fmr-1]) } },
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.load_multi_by_keys(['futures_mgmt_record:fmr-1:object']) } },
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.all } },
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.count! } },
  @refused.call { @in_pipeline.call { FuturesMgmtRecord.any! } },
].uniq
#=> [Familia::OperationModeError]

## class destroy! inside a transaction raises before deleting anything
[@refused.call { FuturesMgmtRecord.transaction { FuturesMgmtRecord.destroy!('fmr-2') } },
 FuturesMgmtRecord.exists?('fmr-2')]
#=> [Familia::OperationModeError, true]

## class destroy! inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { FuturesMgmtRecord.destroy!('fmr-2') } }
#=> Familia::OperationModeError

## count helpers inside atomic_write pass Futures through and persist both writes
@ret, @persisted = @in_atomic_write.call('aw-count') do
  [FuturesMgmtRecord.any?, FuturesMgmtRecord.keys_count, FuturesMgmtRecord.keys_any?,
   FuturesMgmtRecord.in_instances?('fmr-2')]
end
[@ret.map(&:class).uniq, @ret.first.value, @ret[1].value.sort, @persisted]
#=> [[Redis::Future], 2, ["futures_mgmt_record:fmr-1:object", "futures_mgmt_record:fmr-2:object"], "aw-count"]

## count helpers inside a pipeline pass Futures through
@ret = @in_pipeline.call do
  [FuturesMgmtRecord.any?, FuturesMgmtRecord.keys_count, FuturesMgmtRecord.in_instances?('nope')]
end
[@ret.map(&:class).uniq, @ret.last.value]
#=> [[Redis::Future], nil]

## multiget and storage_inspect inside atomic_write pass Futures through
@ret, @persisted = @in_atomic_write.call('aw-inspect') do
  [FuturesMgmtRecord.multiget('fmr-2'), FuturesMgmtRecord.storage_inspect('fmr-2')]
end
[@ret.map(&:class).uniq, @ret.last.value['name'], @persisted]
#=> [[Redis::Future], "\"two\"", "aw-inspect"]

## storage_inspect inside a pipeline passes the HGETALL Future through
@ret = @in_pipeline.call { FuturesMgmtRecord.storage_inspect('futures_mgmt_record:fmr-2:object') }
[@ret.class, @ret.value.keys.sort]
#=> [Redis::Future, ["name", "recid"]]

## outside a block: finders and loaders return records
[FuturesMgmtRecord.load('fmr-2').name, FuturesMgmtRecord.load_multi(%w[fmr-1 fmr-2 nope]).map { |r| r&.recid },
 FuturesMgmtRecord.all.map(&:recid).sort, FuturesMgmtRecord.find_by_id('nope')]
#=> ["two", ["fmr-1", "fmr-2", nil], ["fmr-1", "fmr-2"], nil]

## outside a block: counters keep Integer and Boolean results
[FuturesMgmtRecord.any?, FuturesMgmtRecord.keys_count, FuturesMgmtRecord.keys_any?, FuturesMgmtRecord.scan_count,
 FuturesMgmtRecord.scan_any?, FuturesMgmtRecord.in_instances?('fmr-2'), FuturesMgmtRecord.keys_any?('nope*')]
#=> [true, 2, true, 2, true, true, false]

## outside a block: storage_inspect decodes fields and returns nil for a missing key
[FuturesMgmtRecord.storage_inspect('fmr-2')['name'], FuturesMgmtRecord.storage_inspect('nope')]
#=> [{:raw=>"\"two\"", :decoded=>"two", :type=>"String"}, nil]

# Teardown
delete_test_dbkeys(FuturesMgmtRecord)
