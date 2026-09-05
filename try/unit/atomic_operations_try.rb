# try/unit/atomic_operations_try.rb
#
# frozen_string_literal: true

# Direct unit tests for Familia::AtomicOperations.
#
# Covers the two public primitives that back index rebuilds and audit/repair
# routines:
#   - build_temp_key: unique temp key name (timestamp + random nonce) with
#                     the :rebuild: marker
#   - atomic_swap:    RENAME when temp key exists, DEL otherwise; idempotent
#                     when final_key is absent
#
# Concurrent race detection lives in try/features/relationships/indexing_rebuild_try.rb;
# this file guards against accidental behavioral changes to the module methods
# themselves during future refactors.

require_relative '../support/helpers/test_helpers'
require 'delegate'

# Makes the swap script raise the given error so the preserve-and-raise
# branch is exercised (see memory_leak_proof.rb PROOF C). Lock scripts pass
# through untouched.
class AoFailingSwap < SimpleDelegator
  def initialize(client, error)
    super(client)
    @error = error
  end

  def eval(script, *, **)
    raise @error if script == Familia::AtomicOperations::SWAP_SCRIPT

    __getobj__.eval(script, *, **)
  end
end

# Deletes the temp key just before the real swap script runs, reproducing an
# eviction/expiry/sweep between the EXISTS guard and the RENAME. The script
# then finds no key, which is the fail-open case: the swap did not happen.
class AoVanishingTempKey < SimpleDelegator
  def initialize(client, temp_key)
    super(client)
    @temp_key = temp_key
  end

  def eval(script, *, **)
    __getobj__.del(@temp_key) if script == Familia::AtomicOperations::SWAP_SCRIPT
    __getobj__.eval(script, *, **)
  end
end

# Deletes the temp key on the way into the swap script, after with_rebuild's
# own presence guard has passed. Only the block's own record of what it
# wrote, carried into the script, can make this fail closed.
class AoVanishAfterGuard < SimpleDelegator
  def eval(script, *args, **kwargs)
    __getobj__.del(kwargs.fetch(:keys).first) if script == Familia::AtomicOperations::SWAP_SCRIPT
    __getobj__.eval(script, *args, **kwargs)
  end
end

# Hands the lock to a successor just before the real swap script runs: the
# final touch already passed, so only the fence inside the script can stop
# the stale RENAME.
class AoLockStolenBeforeSwap < SimpleDelegator
  def initialize(client, lock_key)
    super(client)
    @lock_key = lock_key
  end

  def eval(script, *, **)
    __getobj__.set(@lock_key, 'successor', ex: 30) if script == Familia::AtomicOperations::SWAP_SCRIPT
    __getobj__.eval(script, *, **)
  end
end

def ao_reset(*keys)
  Familia.dbclient.del(*keys) if keys.any?
end

## build_temp_key includes the base key prefix
@temp = Familia::AtomicOperations.build_temp_key('myindex:live')
@temp.start_with?('myindex:live:')
#=> true

## build_temp_key includes the :rebuild: marker
Familia::AtomicOperations.build_temp_key('myindex:live').include?(':rebuild:')
#=> true

## build_temp_key suffix is a numeric timestamp followed by a hex nonce
@temp = Familia::AtomicOperations.build_temp_key('x:y')
@suffix = @temp.split(':rebuild:').last
@suffix.match?(/\A\d+:\h{16}\z/)
#=> true

## build_temp_key timestamp component reflects the current time
@ts = @suffix.split(':').first.to_i
(@ts - Familia.now.to_i).abs <= 2
#=> true

## build_temp_key never returns the same key twice for one base key
# Two rebuilds of the same index started within one second must not share a
# temp key, otherwise their contents interleave and one RENAME strands the other.
@first = Familia::AtomicOperations.build_temp_key('same')
@second = Familia::AtomicOperations.build_temp_key('same')
@first == @second
#=> false

## build_temp_key produces distinct keys across many rapid calls
keys = Array.new(1000) { Familia::AtomicOperations.build_temp_key('same') }
keys.uniq.size
#=> 1000

## build_temp_key produces distinct keys across concurrent threads
results = Queue.new
threads = Array.new(8) do
  Thread.new { 50.times { results << Familia::AtomicOperations.build_temp_key('same') } }
end
threads.each(&:join)
keys = Array.new(results.size) { results.pop }
[keys.size, keys.uniq.size]
#=> [400, 400]

## build_temp_key returns a String
Familia::AtomicOperations.build_temp_key('base').is_a?(String)
#=> true

## atomic_swap with populated temp key RENAMEs onto final_key
ao_reset('ao_swap:final', 'ao_swap:temp')
Familia.dbclient.hset('ao_swap:temp', 'field', 'value')
Familia::AtomicOperations.atomic_swap('ao_swap:temp', 'ao_swap:final', Familia.dbclient)
[Familia.dbclient.exists('ao_swap:temp'),
 Familia.dbclient.hget('ao_swap:final', 'field')]
#=> [0, "value"]

## atomic_swap with populated temp key replaces an existing final_key
ao_reset('ao_swap2:final', 'ao_swap2:temp')
Familia.dbclient.hset('ao_swap2:final', 'field', 'old')
Familia.dbclient.hset('ao_swap2:temp', 'field', 'new')
Familia::AtomicOperations.atomic_swap('ao_swap2:temp', 'ao_swap2:final', Familia.dbclient)
Familia.dbclient.hget('ao_swap2:final', 'field')
#=> "new"

## atomic_swap with empty result set DELs the final key
ao_reset('ao_swap3:final', 'ao_swap3:temp')
Familia.dbclient.hset('ao_swap3:final', 'stale', 'value')
Familia::AtomicOperations.atomic_swap('ao_swap3:temp', 'ao_swap3:final', Familia.dbclient)
Familia.dbclient.exists('ao_swap3:final')
#=> 0

## atomic_swap is idempotent when neither temp nor final exists
ao_reset('ao_swap4:final', 'ao_swap4:temp')
Familia::AtomicOperations.atomic_swap('ao_swap4:temp', 'ao_swap4:final', Familia.dbclient)
Familia.dbclient.exists('ao_swap4:final')
#=> 0

## atomic_swap PERSISTs the final key so a temp key TTL is not inherited
ao_reset('ao_ttl:final', 'ao_ttl:temp')
Familia.dbclient.hset('ao_ttl:temp', 'k', 'v')
Familia.dbclient.expire('ao_ttl:temp', 60)
Familia::AtomicOperations.atomic_swap('ao_ttl:temp', 'ao_ttl:final', Familia.dbclient)
Familia.dbclient.ttl('ao_ttl:final')
#=> -1

## atomic_swap failure bounds the preserved temp key with a TTL
ao_reset('ao_fail:final', 'ao_fail:temp')
Familia.dbclient.hset('ao_fail:temp', 'k', 'v')
begin
  Familia::AtomicOperations.atomic_swap(
    'ao_fail:temp', 'ao_fail:final',
    AoFailingSwap.new(Familia.dbclient, Redis::CommandError.new('OOM command not allowed (simulated)')),
    preserve_for: 120
  )
  @ao_fail_raised = false
rescue Redis::CommandError
  @ao_fail_raised = true
end
@ao_fail_ttl = Familia.dbclient.ttl('ao_fail:temp')
[@ao_fail_raised, Familia.dbclient.exists('ao_fail:temp'), @ao_fail_ttl.positive? && @ao_fail_ttl <= 120]
#=> [true, 1, true]

## a connection-level swap failure also bounds the preserved temp key
# Not a CommandError: a dropped connection or timeout must take the same
# retention path, or a direct atomic_swap caller's TTL-less temp key leaks.
ao_reset('ao_fail2:final', 'ao_fail2:temp')
Familia.dbclient.hset('ao_fail2:temp', 'k', 'v')
begin
  Familia::AtomicOperations.atomic_swap(
    'ao_fail2:temp', 'ao_fail2:final',
    AoFailingSwap.new(Familia.dbclient, Redis::TimeoutError.new('Connection timed out (simulated)')),
    preserve_for: 120
  )
  @ao_fail2_raised = false
rescue Redis::TimeoutError
  @ao_fail2_raised = true
end
@ao_fail2_ttl = Familia.dbclient.ttl('ao_fail2:temp')
[@ao_fail2_raised, Familia.dbclient.exists('ao_fail2:temp'), @ao_fail2_ttl.positive? && @ao_fail2_ttl <= 120]
#=> [true, 1, true]

## atomic_swap fenced on a lock it does not hold refuses to publish
ao_reset('ao_fence:final', 'ao_fence:temp', Familia::AtomicOperations.rebuild_lock_key('ao_fence:final'))
Familia.dbclient.hset('ao_fence:final', 'live', 'yes')
Familia.dbclient.hset('ao_fence:temp', 'fresh', 'yes')
Familia.dbclient.set(Familia::AtomicOperations.rebuild_lock_key('ao_fence:final'), 'successor', ex: 30)
begin
  Familia::AtomicOperations.atomic_swap(
    'ao_fence:temp', 'ao_fence:final', Familia.dbclient,
    lock: { key: Familia::AtomicOperations.rebuild_lock_key('ao_fence:final'), token: 'mine' }
  )
  'no error'
rescue Familia::RebuildLockLostError
  [
    Familia.dbclient.hget('ao_fence:final', 'live'),
    Familia.dbclient.hget('ao_fence:final', 'fresh'),
    Familia.dbclient.exists('ao_fence:temp'),
    Familia.dbclient.get(Familia::AtomicOperations.rebuild_lock_key('ao_fence:final')),
  ]
end
#=> ['yes', nil, 0, 'successor']

## atomic_swap rejects a fence with a blank token instead of silently unfencing
ao_reset('ao_fence3:final', 'ao_fence3:temp', Familia::AtomicOperations.rebuild_lock_key('ao_fence3:final'))
Familia.dbclient.hset('ao_fence3:final', 'live', 'yes')
Familia.dbclient.hset('ao_fence3:temp', 'fresh', 'yes')
Familia.dbclient.set(Familia::AtomicOperations.rebuild_lock_key('ao_fence3:final'), 'successor', ex: 30)
begin
  Familia::AtomicOperations.atomic_swap(
    'ao_fence3:temp', 'ao_fence3:final', Familia.dbclient,
    lock: { key: Familia::AtomicOperations.rebuild_lock_key('ao_fence3:final'), token: '' }
  )
  'no error'
rescue ArgumentError
  [Familia.dbclient.hget('ao_fence3:final', 'live'), Familia.dbclient.exists('ao_fence3:temp')]
end
#=> ['yes', 1]

## atomic_swap fenced on a lock it holds publishes and persists
ao_reset('ao_fence2:final', 'ao_fence2:temp', Familia::AtomicOperations.rebuild_lock_key('ao_fence2:final'))
Familia.dbclient.hset('ao_fence2:temp', 'fresh', 'yes')
Familia.dbclient.expire('ao_fence2:temp', 60)
Familia.dbclient.set(Familia::AtomicOperations.rebuild_lock_key('ao_fence2:final'), 'mine', ex: 30)
Familia::AtomicOperations.atomic_swap(
  'ao_fence2:temp', 'ao_fence2:final', Familia.dbclient,
  lock: { key: Familia::AtomicOperations.rebuild_lock_key('ao_fence2:final'), token: 'mine' }
)
[
  Familia.dbclient.hget('ao_fence2:final', 'fresh'),
  Familia.dbclient.ttl('ao_fence2:final'),
  Familia.dbclient.exists('ao_fence2:temp'),
]
#=> ['yes', -1, 0]

## with_rebuild swaps the block's temp key into place and returns the block value
ao_reset('ao_wr:final', Familia::AtomicOperations.rebuild_lock_key('ao_wr:final'))
@ao_wr_result = Familia::AtomicOperations.with_rebuild('ao_wr:final', Familia.dbclient) do |temp_key, touch|
  Familia.dbclient.hset(temp_key, 'a', '1')
  touch.call
  :done
end
[@ao_wr_result, Familia.dbclient.hget('ao_wr:final', 'a'), Familia.dbclient.ttl('ao_wr:final')]
#=> [:done, '1', -1]

## with_rebuild releases the lock on success
Familia.dbclient.exists(Familia::AtomicOperations.rebuild_lock_key('ao_wr:final'))
#=> 0

## touch refreshes the temp key TTL once the key exists
ao_reset('ao_touch:final', Familia::AtomicOperations.rebuild_lock_key('ao_touch:final'))
@ao_touch_ttls = []
Familia::AtomicOperations.with_rebuild('ao_touch:final', Familia.dbclient, ttl: 90) do |temp_key, touch|
  touch.call # key does not exist yet: EXPIRE returns 0, ignored
  @ao_touch_ttls << Familia.dbclient.ttl(temp_key)
  Familia.dbclient.hset(temp_key, 'a', '1')
  touch.call
  @ao_touch_ttls << Familia.dbclient.ttl(temp_key)
end
[@ao_touch_ttls.first, @ao_touch_ttls.last.positive? && @ao_touch_ttls.last <= 90]
#=> [-2, true]

## with_rebuild raises RebuildInProgressError when the lock is held
ao_reset('ao_lock:final')
Familia.dbclient.set(Familia::AtomicOperations.rebuild_lock_key('ao_lock:final'), 'other', ex: 60)
begin
  Familia::AtomicOperations.with_rebuild('ao_lock:final', Familia.dbclient) { |_t, _touch| :never }
  'no error'
rescue Familia::RebuildInProgressError => e
  e.message
end
#=> 'Rebuild already in progress for ao_lock:final'

## a held lock is not stolen or released by the rejected rebuild
Familia.dbclient.get(Familia::AtomicOperations.rebuild_lock_key('ao_lock:final'))
#=> 'other'

## with_rebuild deletes the temp key and leaves the live key alone when the block raises
ao_reset('ao_blockfail:final', Familia::AtomicOperations.rebuild_lock_key('ao_blockfail:final'))
Familia.dbclient.hset('ao_blockfail:final', 'live', 'yes')
@ao_blockfail_temp = nil
begin
  Familia::AtomicOperations.with_rebuild('ao_blockfail:final', Familia.dbclient) do |temp_key, touch|
    @ao_blockfail_temp = temp_key
    Familia.dbclient.hset(temp_key, 'partial', '1')
    touch.call
    raise Familia::Problem, 'batch aborted'
  end
rescue Familia::Problem
  nil
end
[
  Familia.dbclient.exists(@ao_blockfail_temp),
  Familia.dbclient.hget('ao_blockfail:final', 'live'),
  Familia.dbclient.exists(Familia::AtomicOperations.rebuild_lock_key('ao_blockfail:final')),
]
#=> [0, 'yes', 0]

## sweep deletes an old legacy-format temp key with no TTL
ao_reset('ao_sweep1:idx:rebuild:1000000')
Familia.dbclient.hset('ao_sweep1:idx:rebuild:1000000', 'a', '1')
Familia::AtomicOperations.sweep_orphaned_temp_keys(Familia.dbclient, pattern: 'ao_sweep1:*:rebuild:*')
#=> ['ao_sweep1:idx:rebuild:1000000']

## sweep keeps a recent no-TTL temp key
@ao_sweep2 = Familia::AtomicOperations.build_temp_key('ao_sweep2:idx')
ao_reset(@ao_sweep2)
Familia.dbclient.hset(@ao_sweep2, 'a', '1')
[
  Familia::AtomicOperations.sweep_orphaned_temp_keys(Familia.dbclient, pattern: 'ao_sweep2:*:rebuild:*'),
  Familia.dbclient.exists(@ao_sweep2),
]
#=> [[], 1]

## sweep keeps an old temp key that already has a TTL
ao_reset('ao_sweep3:idx:rebuild:1000000:0123456789abcdef')
Familia.dbclient.hset('ao_sweep3:idx:rebuild:1000000:0123456789abcdef', 'a', '1')
Familia.dbclient.expire('ao_sweep3:idx:rebuild:1000000:0123456789abcdef', 300)
[
  Familia::AtomicOperations.sweep_orphaned_temp_keys(Familia.dbclient, pattern: 'ao_sweep3:*:rebuild:*'),
  Familia.dbclient.exists('ao_sweep3:idx:rebuild:1000000:0123456789abcdef'),
]
#=> [[], 1]

## sweep never touches rebuild-lock keys
ao_reset('ao_sweep4:idx:rebuild-lock')
Familia.dbclient.set('ao_sweep4:idx:rebuild-lock', 'token')
[
  Familia::AtomicOperations.sweep_orphaned_temp_keys(Familia.dbclient, pattern: 'ao_sweep4:*'),
  Familia.dbclient.exists('ao_sweep4:idx:rebuild-lock'),
]
#=> [[], 1]

## sweep with dry_run reports without deleting
ao_reset('ao_sweep5:idx:rebuild:1000000:0123456789abcdef')
Familia.dbclient.hset('ao_sweep5:idx:rebuild:1000000:0123456789abcdef', 'a', '1')
[
  Familia::AtomicOperations.sweep_orphaned_temp_keys(
    Familia.dbclient, pattern: 'ao_sweep5:*:rebuild:*', dry_run: true
  ),
  Familia.dbclient.exists('ao_sweep5:idx:rebuild:1000000:0123456789abcdef'),
]
#=> [['ao_sweep5:idx:rebuild:1000000:0123456789abcdef'], 1]

## atomic_swap raises when the temp key vanishes between the guard and the RENAME
# Fail-closed: the RENAME never happened, so the live index is stale and the
# caller must not be told the swap succeeded.
ao_reset('ao_vanish:final', 'ao_vanish:temp')
Familia.dbclient.hset('ao_vanish:final', 'stale', 'yes')
Familia.dbclient.hset('ao_vanish:temp', 'fresh', 'yes')
begin
  Familia::AtomicOperations.atomic_swap(
    'ao_vanish:temp', 'ao_vanish:final', AoVanishingTempKey.new(Familia.dbclient, 'ao_vanish:temp')
  )
  ['reported success', Familia.dbclient.hget('ao_vanish:final', 'stale')]
rescue Familia::PersistenceError => e
  [e.message.include?('vanished during the swap'), Familia.dbclient.hget('ao_vanish:final', 'stale')]
end
#=> [true, 'yes']

## touch raises RebuildLockLostError when another rebuild steals the lock
ao_reset('ao_steal:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal:final'))
Familia.dbclient.hset('ao_steal:final', 'live', 'yes')
@ao_steal_temp = nil
begin
  Familia::AtomicOperations.with_rebuild('ao_steal:final', Familia.dbclient) do |temp_key, touch|
    @ao_steal_temp = temp_key
    Familia.dbclient.hset(temp_key, 'fresh', 'yes')
    # Simulate a successor taking over after this rebuild stalled past the TTL.
    Familia.dbclient.set(Familia::AtomicOperations.rebuild_lock_key('ao_steal:final'), 'successor', ex: 30)
    touch.call
    :never
  end
  'no error'
rescue Familia::RebuildLockLostError => e
  e.message
end
#=> 'Rebuild lock lost for ao_steal:final: another rebuild took over'

## a lost lock aborts before the swap, dropping the temp key and sparing the live key
[
  Familia.dbclient.exists(@ao_steal_temp),
  Familia.dbclient.hget('ao_steal:final', 'live'),
  Familia.dbclient.hget('ao_steal:final', 'fresh'),
  Familia.dbclient.get(Familia::AtomicOperations.rebuild_lock_key('ao_steal:final')),
]
#=> [0, 'yes', nil, 'successor']

## a lock lost only at the end of the block still prevents the swap
Familia.dbclient.del(Familia::AtomicOperations.rebuild_lock_key('ao_steal2:final'))
ao_reset('ao_steal2:final')
Familia.dbclient.hset('ao_steal2:final', 'live', 'yes')
begin
  Familia::AtomicOperations.with_rebuild('ao_steal2:final', Familia.dbclient) do |temp_key, _touch|
    Familia.dbclient.hset(temp_key, 'fresh', 'yes')
    # No touch call inside the block: ownership is re-verified before the swap.
    Familia.dbclient.set(Familia::AtomicOperations.rebuild_lock_key('ao_steal2:final'), 'successor', ex: 30)
    :never
  end
  'no error'
rescue Familia::RebuildLockLostError
  [Familia.dbclient.hget('ao_steal2:final', 'live'), Familia.dbclient.hget('ao_steal2:final', 'fresh')]
end
#=> ['yes', nil]

## a lock lost after the final touch is caught by the fence inside the swap
# The last touch passes, then the lock changes hands before the swap script
# runs. Only an ownership check atomic with the RENAME can stop this one.
ao_reset('ao_steal3:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal3:final'))
Familia.dbclient.hset('ao_steal3:final', 'live', 'yes')
@ao_steal3_temp = nil
begin
  Familia::AtomicOperations.with_rebuild(
    'ao_steal3:final',
    AoLockStolenBeforeSwap.new(Familia.dbclient, Familia::AtomicOperations.rebuild_lock_key('ao_steal3:final')),
  ) do |temp_key, touch|
    @ao_steal3_temp = temp_key
    Familia.dbclient.hset(temp_key, 'fresh', 'yes')
    touch.call
    :never
  end
  'no error'
rescue Familia::RebuildLockLostError
  [
    Familia.dbclient.hget('ao_steal3:final', 'live'),
    Familia.dbclient.hget('ao_steal3:final', 'fresh'),
    Familia.dbclient.exists(@ao_steal3_temp),
    Familia.dbclient.get(Familia::AtomicOperations.rebuild_lock_key('ao_steal3:final')),
  ]
end
#=> ['yes', nil, 0, 'successor']

## sweep keeps an old no-TTL temp key whose rebuild lock is still held
ao_reset('ao_sweep6:idx:rebuild:1000000', 'ao_sweep6:idx:rebuild-lock')
Familia.dbclient.hset('ao_sweep6:idx:rebuild:1000000', 'a', '1')
Familia.dbclient.set('ao_sweep6:idx:rebuild-lock', 'token', ex: 60)
[
  Familia::AtomicOperations.sweep_orphaned_temp_keys(Familia.dbclient, pattern: 'ao_sweep6:*:rebuild:*'),
  Familia.dbclient.exists('ao_sweep6:idx:rebuild:1000000'),
]
#=> [[], 1]

## with_rebuild refuses to run inside a transaction
ao_reset('ao_txn:final')
begin
  Familia.transaction do |_tx|
    Familia::AtomicOperations.with_rebuild('ao_txn:final', Familia.dbclient) { |_t, _touch| :never }
  end
  'no error'
rescue Familia::OperationModeError => e
  e.message.include?('cannot run inside a transaction')
end
#=> true

## with_rebuild refuses to run inside a pipeline
# Separate Fiber[:familia_pipeline] branch of the guard; no lock or temp key
# may be left behind by the rejected call.
ao_reset('ao_pipe:final')
begin
  Familia.pipelined do |_pipe|
    Familia::AtomicOperations.with_rebuild('ao_pipe:final', Familia.dbclient) { |_t, _touch| :never }
  end
  'no error'
rescue Familia::OperationModeError => e
  [
    e.message.include?('cannot run inside a transaction or pipeline'),
    Familia.dbclient.exists(Familia::AtomicOperations.rebuild_lock_key('ao_pipe:final')),
    Familia.dbclient.scan_each(match: 'ao_pipe:final:rebuild:*').to_a,
  ]
end
#=> [true, 0, []]

## with_rebuild fails closed when the temp key vanishes after the presence guard
# The block wrote a batch, assert_temp_key_present! passed, then the key is
# gone by the time the swap script runs. Without populated: carried into the
# script, the swap would read it as an empty rebuild and DEL the live index.
ao_reset('ao_gone2:final', Familia::AtomicOperations.rebuild_lock_key('ao_gone2:final'))
Familia.dbclient.hset('ao_gone2:final', 'live', 'yes')
begin
  Familia::AtomicOperations.with_rebuild(
    'ao_gone2:final',
    AoVanishAfterGuard.new(Familia.dbclient),
  ) do |temp_key, touch|
    Familia.dbclient.hset(temp_key, 'fresh', 'yes')
    touch.call
    :never
  end
  ['no error', Familia.dbclient.hget('ao_gone2:final', 'live')]
rescue Familia::PersistenceError => e
  [e.message.include?('vanished during the swap'), Familia.dbclient.hget('ao_gone2:final', 'live')]
end
#=> [true, 'yes']

## with_rebuild fails closed when a populated temp key vanishes before the swap
# Without the temp_seen guard, atomic_swap reads the missing key as an empty
# result set and DELs the live index while reporting success.
ao_reset('ao_gone:final', Familia::AtomicOperations.rebuild_lock_key('ao_gone:final'))
Familia.dbclient.hset('ao_gone:final', 'live', 'yes')
begin
  Familia::AtomicOperations.with_rebuild('ao_gone:final', Familia.dbclient, ttl: 60) do |temp_key, touch|
    Familia.dbclient.hset(temp_key, 'fresh', 'yes')
    touch.call
    Familia.dbclient.del(temp_key) # eviction / expiry / sweep
    :never
  end
  ['no error', Familia.dbclient.hget('ao_gone:final', 'live')]
rescue Familia::PersistenceError => e
  [e.message.include?('vanished before the swap'), Familia.dbclient.hget('ao_gone:final', 'live')]
end
#=> [true, 'yes']

## an empty rebuild still DELs the live key (no batch was ever written)
ao_reset('ao_empty:final', Familia::AtomicOperations.rebuild_lock_key('ao_empty:final'))
Familia.dbclient.hset('ao_empty:final', 'stale', 'yes')
Familia::AtomicOperations.with_rebuild('ao_empty:final', Familia.dbclient) { |_t, touch| touch.call }
Familia.dbclient.exists('ao_empty:final')
#=> 0

# Teardown
ao_reset(
  'ao_swap:final', 'ao_swap:temp',
  'ao_swap2:final', 'ao_swap2:temp',
  'ao_swap3:final', 'ao_swap3:temp',
  'ao_swap4:final', 'ao_swap4:temp',
  'ao_ttl:final', 'ao_ttl:temp',
  'ao_fail:final', 'ao_fail:temp', 'ao_fail2:final', 'ao_fail2:temp',
  'ao_fence:final', 'ao_fence:temp', Familia::AtomicOperations.rebuild_lock_key('ao_fence:final'),
  'ao_fence2:final', 'ao_fence2:temp', Familia::AtomicOperations.rebuild_lock_key('ao_fence2:final'),
  'ao_fence3:final', 'ao_fence3:temp', Familia::AtomicOperations.rebuild_lock_key('ao_fence3:final'),
  'ao_gone2:final', Familia::AtomicOperations.rebuild_lock_key('ao_gone2:final'),
  'ao_wr:final', 'ao_touch:final', 'ao_blockfail:final',
  'ao_lock:final', Familia::AtomicOperations.rebuild_lock_key('ao_lock:final'),
  'ao_sweep2:idx', 'ao_sweep3:idx:rebuild:1000000:0123456789abcdef',
  'ao_sweep4:idx:rebuild-lock', 'ao_sweep5:idx:rebuild:1000000:0123456789abcdef',
  @ao_sweep2, @ao_steal_temp,
  'ao_vanish:final', 'ao_vanish:temp', 'ao_txn:final', 'ao_pipe:final',
  'ao_steal3:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal3:final'), @ao_steal3_temp,
  'ao_steal:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal:final'),
  'ao_steal2:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal2:final'),
  'ao_sweep6:idx:rebuild:1000000', 'ao_sweep6:idx:rebuild-lock',
  'ao_gone:final', Familia::AtomicOperations.rebuild_lock_key('ao_gone:final'),
  'ao_empty:final', Familia::AtomicOperations.rebuild_lock_key('ao_empty:final'),
)
