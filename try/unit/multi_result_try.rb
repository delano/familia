# try/unit/multi_result_try.rb
#
# frozen_string_literal: true

# Tests for Familia::MultiResult - wraps the return values of a MULTI/EXEC
# transaction or a pipeline.
#
# Three outcomes are distinguished:
#   - committed cleanly    -> results is an array with no Exception members
#   - committed with errors -> results is an array containing Exception objects
#   - aborted (issue #355)  -> results is nil, because redis-rb returns nil from
#     #multi when EXEC is discarded (a WATCH-guarded transaction whose watched
#     key changed under it). Accessors must report failure, not raise.

require_relative '../support/helpers/test_helpers'

@ok = Familia::MultiResult.new(['OK', 'OK', 1])
@failed = Familia::MultiResult.new(['OK', Redis::CommandError.new('WRONGTYPE'), 1])
@empty = Familia::MultiResult.new([])
@aborted = Familia::MultiResult.new(nil)

@watch_key = 'multiresult:watch_abort'

# ============================================================
# Clean results
# ============================================================

## A clean result exposes the raw command return values
@ok.results
#=> ['OK', 'OK', 1]

## A clean result is successful
@ok.successful?
#=> true

## A clean result has no errors
@ok.errors
#=> []

## A clean result reports errors? false
@ok.errors?
#=> false

## A clean result is not aborted
@ok.aborted?
#=> false

## A clean result counts its command return values
@ok.size
#=> 3

## A clean result tuples to [true, results]
@ok.tuple
#=> [true, ['OK', 'OK', 1]]

## A clean result hashes to success: true
@ok.to_h
#=> { success: true, results: ['OK', 'OK', 1]  }

# ============================================================
# Results carrying command errors
# ============================================================

## A result with an Exception member collects it in errors
@failed.errors.size
#=> 1

## A result with an Exception member reports errors?
@failed.errors?
#=> true

## A result with an Exception member is not successful
@failed.successful?
#=> false

## A result with an Exception member is not aborted -- the commands did run
@failed.aborted?
#=> false

## A result with an Exception member still counts every return value
@failed.size
#=> 3

# ============================================================
# Empty results (a transaction that queued no commands)
# ============================================================

## An empty result is successful -- nothing ran, nothing failed
@empty.successful?
#=> true

## An empty result is not aborted
@empty.aborted?
#=> false

## An empty result has size zero
@empty.size
#=> 0

# ============================================================
# Aborted results (nil) -- issue #355
# ============================================================

## An aborted result reports aborted?
@aborted.aborted?
#=> true

## An aborted result is NOT successful (previously raised NoMethodError)
@aborted.successful?
#=> false

## success? alias agrees with successful? on an aborted result
@aborted.success?
#=> false

## areyouhappynow? alias agrees with successful? on an aborted result
@aborted.areyouhappynow?
#=> false

## An aborted result returns an empty errors array (previously raised)
@aborted.errors
#=> []

## An aborted result reports errors? false -- it failed, but no command errored
@aborted.errors?
#=> false

## The empty errors array is frozen, since it is shared across aborted results
@aborted.errors.frozen?
#=> true

## An aborted result has size zero (previously raised)
@aborted.size
#=> 0

## An aborted result preserves nil in #results, so callers can tell it apart
## from a transaction that committed zero commands
@aborted.results
#=> nil

## An aborted result tuples to [false, nil]
@aborted.tuple
#=> [false, nil]

## to_a is the tuple alias and also survives an aborted result
@aborted.to_a
#=> [false, nil]

## An aborted result hashes to success: false (previously raised)
@aborted.to_h
#=> { success: false, results: nil }

## Repeated calls stay stable -- memoization must not cache a bad value
[@aborted.errors, @aborted.errors, @aborted.successful?, @aborted.successful?]
#=> [[], [], false, false]

# ============================================================
# Real WATCH-aborted MULTI against the database
# ============================================================

## A WATCH abort really does produce a MultiResult wrapping nil.
## Drive WATCH + MULTI/EXEC on one connection while a SECOND connection
## dirties the watched key inside the WATCH window, so Redis discards EXEC.
@conn = Redis.new(url: Familia.uri.to_s)
@racer = Redis.new(url: Familia.uri.to_s)
@conn.set(@watch_key, 'original')
@real_abort = @conn.watch(@watch_key) do
  @racer.set(@watch_key, 'changed-by-racer')
  Familia::Connection::TransactionCore.execute_normal_transaction(-> { @conn }) do |txn|
    txn.set(@watch_key, 'from-transaction')
  end
end
[@real_abort.class, @real_abort.results]
#=> [Familia::MultiResult, nil]

## The aborted transaction reports failure rather than raising NoMethodError
[@real_abort.successful?, @real_abort.errors, @real_abort.errors?, @real_abort.size]
#=> [false, [], false, 0]

## The aborted transaction applied none of its commands
@conn.get(@watch_key)
#=> 'changed-by-racer'

## An uncontended WATCH-guarded transaction still commits normally
@conn.set(@watch_key, 'original')
@committed = @conn.watch(@watch_key) do
  Familia::Connection::TransactionCore.execute_normal_transaction(-> { @conn }) do |txn|
    txn.set(@watch_key, 'from-transaction')
  end
end
[@committed.aborted?, @committed.successful?, @conn.get(@watch_key)]
#=> [false, true, 'from-transaction']

## execute_watched_transaction turns the abort into a retry, then raises
## OptimisticLockError once attempts are exhausted -- it must not crash on
## the nil-carrying MultiResult it inspects to detect the abort.
@attempts = 0
begin
  Familia::Connection::TransactionCore.execute_watched_transaction(
    -> { @conn }, watch_keys: [@watch_key], max_attempts: 2
  ) do |conn|
    @attempts += 1
    @racer.set(@watch_key, "racer-#{@attempts}")
    Familia::Connection::TransactionCore.execute_normal_transaction(-> { conn }) do |txn|
      txn.set(@watch_key, 'should-not-persist')
    end
  end
  :no_raise
rescue Familia::OptimisticLockError
  :raised
end
#=> :raised

## Both attempts ran and the racer's value survived (no silent overwrite)
[@attempts, @racer.get(@watch_key)]
#=> [2, 'racer-2']

@conn.del(@watch_key)
@conn.close
@racer.close
