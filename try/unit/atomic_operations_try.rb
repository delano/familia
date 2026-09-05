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

# Forces the swap MULTI to fail with a non-"no such key" CommandError so the
# preserve-and-raise branch is exercised (see memory_leak_proof.rb PROOF C).
class AoFailingSwap < SimpleDelegator
  def multi(*)
    raise Redis::CommandError, 'OOM command not allowed (simulated)'
  end

  def rename(*)
    raise Redis::CommandError, 'OOM command not allowed (simulated)'
  end
end

# Deletes the temp key just before the real MULTI runs, reproducing an
# eviction/expiry/sweep between the EXISTS guard and EXEC. The RENAME then
# fails server-side, which is the fail-open case: the swap did not happen.
class AoVanishingTempKey < SimpleDelegator
  def initialize(client, temp_key)
    super(client)
    @temp_key = temp_key
  end

  def multi(*args, &block)
    __getobj__.del(@temp_key)
    __getobj__.multi(*args, &block)
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
    'ao_fail:temp', 'ao_fail:final', AoFailingSwap.new(Familia.dbclient), preserve_for: 120
  )
  @ao_fail_raised = false
rescue Redis::CommandError
  @ao_fail_raised = true
end
@ao_fail_ttl = Familia.dbclient.ttl('ao_fail:temp')
[@ao_fail_raised, Familia.dbclient.exists('ao_fail:temp'), @ao_fail_ttl.positive? && @ao_fail_ttl <= 120]
#=> [true, 1, true]

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

## atomic_swap raises when the temp key vanishes between the guard and EXEC
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
rescue Redis::CommandError
  ['raised', Familia.dbclient.hget('ao_vanish:final', 'stale')]
end
#=> ['raised', 'yes']

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
  'ao_fail:final', 'ao_fail:temp',
  'ao_wr:final', 'ao_touch:final', 'ao_blockfail:final',
  'ao_lock:final', Familia::AtomicOperations.rebuild_lock_key('ao_lock:final'),
  'ao_sweep2:idx', 'ao_sweep3:idx:rebuild:1000000:0123456789abcdef',
  'ao_sweep4:idx:rebuild-lock', 'ao_sweep5:idx:rebuild:1000000:0123456789abcdef',
  @ao_sweep2, @ao_steal_temp,
  'ao_vanish:final', 'ao_vanish:temp', 'ao_txn:final',
  'ao_steal:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal:final'),
  'ao_steal2:final', Familia::AtomicOperations.rebuild_lock_key('ao_steal2:final'),
  'ao_sweep6:idx:rebuild:1000000', 'ao_sweep6:idx:rebuild-lock',
  'ao_gone:final', Familia::AtomicOperations.rebuild_lock_key('ao_gone:final'),
  'ao_empty:final', Familia::AtomicOperations.rebuild_lock_key('ao_empty:final'),
)
