# try/integration/futures/expiration_futures_try.rb
#
# frozen_string_literal: true

# Expiration feature methods inside transaction, atomic_write and pipelined
# blocks, on both a Horreum record and a DataType. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Record with a TTL and one related list, so the TTL methods have keys to report on.
class FuturesTtlRecord < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :recid
  field :recid
  field :name
  list :history
end

delete_test_dbkeys(FuturesTtlRecord)

@rec = FuturesTtlRecord.new(recid: 'ftr-1', name: 'original')
@rec.save
@rec.history.push('boot')

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @rec.atomic_write do
    @rec.name = name
    captured = blk.call
  end
  [captured, FuturesTtlRecord.load('ftr-1').name]
end

@in_pipeline = lambda do |&blk|
  captured = nil
  @rec.pipelined { captured = blk.call }
  captured
end

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## Horreum#expired? inside atomic_write passes the TTL Future through
@ret, @persisted = @in_atomic_write.call('aw-expired') { @rec.expired? }
[@ret.class, @ret.value.positive?, @persisted]
#=> [Redis::Future, true, "aw-expired"]

## Horreum#expired? inside a pipeline passes the TTL Future through
@ret = @in_pipeline.call { @rec.expired?(60) }
[@ret.class, @ret.value.positive?]
#=> [Redis::Future, true]

## DataType#expired? inside atomic_write passes the TTL Future through
@ret, @persisted = @in_atomic_write.call('aw-dt-expired') { @rec.history.expired? }
[@ret.class, @ret.value.positive?, @persisted]
#=> [Redis::Future, true, "aw-dt-expired"]

## DataType#expired? inside a transaction passes the TTL Future through
@ret = nil
@rec.transaction { @ret = @rec.history.expired? }
@ret.class
#=> Redis::Future

## Horreum#extend_expiration inside atomic_write raises and persists nothing
@err_class = @refused.call { @in_atomic_write.call('aw-extend') { @rec.extend_expiration(60) } }
[@err_class, FuturesTtlRecord.load('ftr-1').name == 'aw-extend']
#=> [Familia::OperationModeError, false]

## Horreum#extend_expiration inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { @rec.extend_expiration(60) } }
#=> Familia::OperationModeError

## DataType#extend_expiration inside a transaction raises OperationModeError
@refused.call { @rec.transaction { @rec.history.extend_expiration(60) } }
#=> Familia::OperationModeError

## Horreum#ttl_report inside atomic_write raises OperationModeError
@refused.call { @in_atomic_write.call('aw-report') { @rec.ttl_report } }
#=> Familia::OperationModeError

## Horreum#ttl_report inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { @rec.ttl_report } }
#=> Familia::OperationModeError

## outside a block: expired? returns Booleans for live, TTL-less and missing keys
@rec.expire(3600)
@missing = FuturesTtlRecord.new(recid: 'ftr-missing')
@rec.history.persist
[@rec.expired?, @rec.expired?(7200), @rec.history.expired?, @missing.expired?]
#=> [false, true, false, true]

## outside a block: extend_expiration adds to a live TTL and refuses a TTL-less key
@rec.expire(100)
[@rec.extend_expiration(1000), @rec.ttl > 1000, @rec.history.extend_expiration(10)]
#=> [true, true, false]

## outside a block: ttl_report still reports the main key and its relations
@report = @rec.ttl_report
[@report[:main][:key], @report[:relations].keys]
#=> ["futures_ttl_record:ftr-1:object", [:history]]

# Teardown
delete_test_dbkeys(FuturesTtlRecord)
