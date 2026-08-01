# try/unit/multi_result_try.rb
#
# frozen_string_literal: true

# Tests for Familia::MultiResult - wraps the return values of a MULTI/EXEC
# transaction or a pipeline.
#
# Three outcomes are distinguished:
#   - committed cleanly     -> results has no Exception members
#   - committed with errors  -> results contains Exception objects
#   - aborted (issue #355)   -> redis-rb returned nil from #multi because EXEC
#     was discarded (a WATCH-guarded transaction whose watched key changed
#     under it). Accessors must report failure, not raise.
#
# #results is normalized to an Array in every case, so callers can index and
# iterate it unconditionally; #aborted? carries the abort/empty-commit
# distinction that the nil used to carry.

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

## A clean result hashes to success: true, aborted: false
@ok.to_h
#=> { success: true, aborted: false, results: ['OK', 'OK', 1] }

## A clean result inspects without dumping the command return values
@ok.inspect
#=> '#<Familia::MultiResult ok size=3>'

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

## A result with an Exception member inspects with the error count
@failed.inspect
#=> '#<Familia::MultiResult errors=1 size=3>'

# ============================================================
# Empty results (an operation that queued no commands)
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
# Aborted results -- issue #355
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

## An aborted result has size zero (previously raised)
@aborted.size
#=> 0

## An aborted result normalizes nil to an empty array, so callers can index
## and iterate #results without a nil check
[@aborted.results, @aborted.results[0], @aborted.results.map(&:to_s)]
#=> [[], nil, []]

## An aborted result tuples to [false, []]
@aborted.tuple
#=> [false, []]

## to_a is the tuple alias and also survives an aborted result
@aborted.to_a
#=> [false, []]

## An aborted result hashes to success: false, aborted: true -- a dumped
## failure has to say WHY it failed, or it reads as errors gone missing
@aborted.to_h
#=> { success: false, aborted: true, results: [] }

## An aborted result inspects as aborted
@aborted.inspect
#=> '#<Familia::MultiResult aborted size=0>'

## Repeated calls stay stable -- memoization must not cache a bad value
[@aborted.errors, @aborted.errors, @aborted.successful?, @aborted.successful?]
#=> [[], [], false, false]

# ============================================================
# Abort vs. zero-command commit
# ============================================================

## An abort and an empty commit both report an empty #results, so #aborted?
## is the only thing that separates them -- the distinction the raw nil used
## to carry has to survive the normalization
[@aborted.results, @empty.results]
#=> [[], []]

## ... and it does: only one of them is an abort, and only one is successful
[@aborted.aborted?, @empty.aborted?, @aborted.successful?, @empty.successful?]
#=> [true, false, false, true]

# ============================================================
# A result is read-only -- it describes a finished operation
# ============================================================

## #errors is frozen for a clean result
@ok.errors.frozen?
#=> true

## #errors is frozen for a result carrying command errors
@failed.errors.frozen?
#=> true

## #errors is frozen for an aborted result, so mutating it fails the same way
## regardless of outcome rather than only on some
@aborted.errors.frozen?
#=> true

## Mutating #errors raises rather than silently corrupting the memo
@ok.errors << 'nope'
#=!> FrozenError

## #results is frozen too. #errors is a memo derived from it, so a result
## whose #results could still change after #errors was computed could hold
## the two disagreeing -- freezing the source makes that unreachable.
@ok.results << 'nope'
#=!> FrozenError

## The memo and its source cannot drift: appending an Exception to #results
## after #errors is computed is refused outright rather than silently leaving
## a stale error list behind
drifter = Familia::MultiResult.new(['OK'])
before = drifter.errors.size
begin
  drifter.results << Redis::CommandError.new('late')
rescue FrozenError
  :refused
end.then { |outcome| [before, outcome, drifter.errors.size, drifter.successful?] }
#=> [0, :refused, 0, true]

## to_h hands out that same frozen array, so a caller cannot reach through
## the hash to mutate internal state
@ok.to_h[:results] << 'nope'
#=!> FrozenError

## Each result still owns its own array -- normalizing must not hand every
## aborted result one shared object
a = Familia::MultiResult.new(nil)
b = Familia::MultiResult.new(nil)
[a.results, b.results, a.results.equal?(b.results), a.results.frozen?]
#=> [[], [], false, true]

# ============================================================
# Real WATCH-aborted MULTI against the database
# ============================================================

## A WATCH abort really does produce an aborted MultiResult.
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
[@real_abort.class, @real_abort.aborted?]
#=> [Familia::MultiResult, true]

## The aborted transaction reports failure rather than raising NoMethodError
[@real_abort.successful?, @real_abort.errors, @real_abort.errors?, @real_abort.size, @real_abort.results]
#=> [false, [], false, 0, []]

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
## the aborted MultiResult it inspects to detect the abort.
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
