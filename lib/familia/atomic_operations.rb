# lib/familia/atomic_operations.rb
#
# frozen_string_literal: true

require 'securerandom'

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  # AtomicOperations provides Redis utilities for atomic, zero-downtime data
  # replacement. These primitives are datastore-level building blocks shared
  # across index rebuilds, audit/repair routines, and any other code that
  # needs to swap a key's contents without exposing a transient empty state.
  #
  # The canonical pattern is {.with_rebuild}, which owns the whole lifecycle:
  # exclusive lock, bounded-TTL temp key, atomic swap, and cleanup.
  #
  # All methods are module-level; call them directly on the module.
  #
  # @example Atomic index rebuild
  #   Familia::AtomicOperations.with_rebuild(final_key, redis) do |temp_key, touch|
  #     batches.each do |batch|
  #       write_batch(temp_key, batch)
  #       touch.call
  #     end
  #   end
  #
  module AtomicOperations
    # Lifetime of the rebuild lock and of the temp key between {#touch}
    # refreshes. A single batch must complete within this window.
    DEFAULT_REBUILD_TTL = 300

    # How long a temp key is retained for diagnostics after a failed swap.
    DEFAULT_PRESERVE_TTL = 3600

    # Suffix shapes {.sweep_orphaned_temp_keys} recognizes: the current
    # "<timestamp>:<16 hex nonce>" form and the legacy timestamp-only form.
    TEMP_KEY_SUFFIX_PATTERN = /:rebuild:(\d+)(?::\h{16})?\z/

    # Compare-and-delete: release the lock only if we still hold the token.
    # Mirrors the CAS style used by the unique-index claim scripts.
    RELEASE_LOCK_SCRIPT = <<~LUA
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        return redis.call('DEL', KEYS[1])
      end
      return 0
    LUA

    # Compare-and-extend: refresh the lock TTL only while we still own it.
    # A blind EXPIRE would let a stalled rebuild keep extending the lock a
    # successor already took over, and then swap its stale snapshot on top.
    #
    # @return [Integer] 1 when extended, -1 when the token no longer matches
    EXTEND_LOCK_SCRIPT = <<~LUA
      if redis.call('GET', KEYS[1]) == ARGV[1] then
        redis.call('EXPIRE', KEYS[1], ARGV[2])
        return 1
      end
      return -1
    LUA

    # Builds a unique temporary key name for atomic swaps.
    #
    # The suffix combines a second-resolution timestamp with a 64-bit random
    # nonce. The timestamp keeps orphaned keys sortable by age for sweeps
    # matching `*:rebuild:*`; the nonce guarantees that two rebuilds of the
    # same base key started within the same second (in any thread or
    # process) never write into the same temporary key. Without it, one
    # rebuild could RENAME a mixture of both rebuilds' contents onto the
    # live key and the other would then find its temp key gone.
    #
    # @param base_key [String] The final index key
    # @return [String] Temporary key in the form
    #   "<base_key>:rebuild:<timestamp>:<nonce>"
    #
    def self.build_temp_key(base_key)
      timestamp = Familia.now.to_i
      nonce = SecureRandom.hex(8)
      "#{base_key}:rebuild:#{timestamp}:#{nonce}"
    end

    # The advisory lock key guarding rebuilds of +final_key+.
    #
    # Deliberately does NOT match the `*:rebuild:*` sweep pattern, so a
    # sweep can never delete a live lock.
    #
    # @param final_key [String] The live index key
    # @return [String]
    #
    def self.rebuild_lock_key(final_key)
      "#{final_key}:rebuild-lock"
    end

    # Runs a rebuild of +final_key+ under an exclusive lock, with a bounded
    # temp key, and swaps the result into place.
    #
    # Sequence:
    #   1. Acquire "<final_key>:rebuild-lock" with SET NX EX (fail fast).
    #   2. Build a unique temp key.
    #   3. Yield (temp_key, touch). The block writes batches into temp_key
    #      and calls +touch+ after each one.
    #   4. On normal exit, {.atomic_swap} temp_key -> final_key.
    #   5. On block failure, DEL temp_key; the live index is untouched.
    #   6. Always release the lock (compare-and-delete on our token).
    #
    # A single batch must complete within +ttl+ seconds: the temp key and
    # the lock only survive that long between +touch+ calls.
    #
    # @param final_key [String] The live key being rebuilt
    # @param redis [Redis] Raw connection used for lock/TTL/swap commands
    # @param ttl [Integer] Lock and temp-key TTL, refreshed by +touch+
    # @param preserve_for [Integer] Diagnostic retention after a failed swap
    # @yieldparam temp_key [String]
    # @yieldparam touch [#call] Refreshes the temp key and lock TTLs
    # @return [Object] The block's return value
    # @raise [Familia::RebuildInProgressError] If the lock is already held
    # @raise [Familia::RebuildLockLostError] If the lock was taken over mid-rebuild
    # @raise [Familia::PersistenceError] If a populated temp key vanished before the swap
    # @raise [Familia::OperationModeError] If called inside a transaction or pipeline
    #
    def self.with_rebuild(final_key, redis, ttl: DEFAULT_REBUILD_TTL, preserve_for: DEFAULT_PRESERVE_TTL, &)
      assert_rebuild_context!
      lock_key = rebuild_lock_key(final_key)
      token = SecureRandom.hex(16)
      acquire_rebuild_lock!(redis, lock_key, token, ttl, final_key)

      temp_key = build_temp_key(final_key)
      seen = [false] # whether any batch has been written to temp_key
      lock = { key: lock_key, token: token, ttl: ttl }
      touch = build_touch(redis, temp_key, final_key, lock, seen)

      begin
        result = run_rebuild_block(redis, temp_key, touch, &)
        assert_temp_key_present!(redis, temp_key, final_key, seen[0])
        # A swap failure keeps the temp key on a bounded diagnostic window
        # (see .atomic_swap); it must not fall into the block cleanup.
        atomic_swap(temp_key, final_key, redis, preserve_for: preserve_for)
        result
      ensure
        begin
          redis.eval(RELEASE_LOCK_SCRIPT, keys: [lock_key], argv: [token])
        rescue StandardError => e
          Familia.warn "[AtomicOp] Failed to release rebuild lock #{lock_key}: #{e.message}"
        end
      end
    end

    # Refuses to rebuild inside a transaction/pipeline, where dbclient hands
    # back the MULTI proxy and SET NX only returns a queued-command
    # placeholder -- exclusion could not be enforced.
    #
    def self.assert_rebuild_context!
      return unless Fiber[:familia_transaction] || Fiber[:familia_pipeline]

      raise Familia::OperationModeError,
            'with_rebuild cannot run inside a transaction or pipeline: the lock SET NX ' \
            'only returns a queued-command placeholder, so exclusion cannot be enforced. ' \
            'Run the rebuild outside the multi/pipeline block.'
    end

    def self.acquire_rebuild_lock!(redis, lock_key, token, ttl, final_key)
      return if redis.set(lock_key, token, nx: true, ex: ttl)

      raise Familia::RebuildInProgressError, final_key
    end

    # Builds the per-batch +touch+ callable.
    #
    # Order matters: extend the lock FIRST, then the temp key. The temp key
    # deadline is therefore never earlier than the lock's, so a stall long
    # enough to lose the temp key has already lost the lock and takes the
    # RebuildLockLostError path instead of swapping a vanished key.
    #
    # EXPIRE cannot precede the key: HSET/ZADD is what creates temp_key, so a
    # 0 return simply means "no batch written yet". A 1 return is proof the
    # block has written something, which is what +seen+ records.
    #
    # @param lock [Hash] +{key:, token:, ttl:}+ describing the held lock
    #
    def self.build_touch(redis, temp_key, final_key, lock, seen)
      lambda do
        raise Familia::RebuildLockLostError, final_key unless lock_held?(redis, lock[:key], lock[:token], lock[:ttl])

        seen[0] = true if [1, true].include?(redis.expire(temp_key, lock[:ttl]))
        nil
      end
    end

    # Runs the caller's block, then re-verifies lock ownership before the
    # swap so a stalled rebuild cannot overwrite its successor's newer index.
    # Any failure drops the partial temp key and leaves the live key alone.
    #
    def self.run_rebuild_block(redis, temp_key, touch)
      value = yield(temp_key, touch)
      touch.call
      value
    rescue StandardError
      begin
        redis.del(temp_key)
      rescue StandardError => e
        Familia.warn "[AtomicOp] Failed to clean up temp key #{temp_key}: #{e.message}"
      end
      raise
    end

    # Fails closed when the block populated the temp key but it is gone now:
    # expired, evicted, or swept. atomic_swap would read that as an empty
    # result set and DEL the live index. Direct atomic_swap callers, which
    # have no such history, are unaffected.
    #
    def self.assert_temp_key_present!(redis, temp_key, final_key, temp_seen)
      return unless temp_seen && redis.exists(temp_key).zero?

      raise Familia::PersistenceError,
            "Rebuild temp key #{temp_key} vanished before the swap; #{final_key} left unchanged"
    end

    # Compare-and-extend the rebuild lock.
    #
    # @return [Boolean] true while this token still owns the lock
    #
    def self.lock_held?(redis, lock_key, token, ttl)
      redis.eval(EXTEND_LOCK_SCRIPT, keys: [lock_key], argv: [token, ttl]).to_i == 1
    end

    # Performs atomic swap of temp key to final key.
    #
    # Non-empty rebuilds use Redis RENAME (>= 2.6), which atomically
    # replaces final_key if it exists. Readers observe either the old
    # index or the new one; there is no window in which final_key is
    # absent. This avoids the partial-update, race-condition, and
    # stale-visibility problems of a two-step DEL+RENAME sequence.
    #
    # RENAME carries the source key's TTL with it. Since {.with_rebuild}
    # puts a bounded TTL on the temp key, the RENAME is paired with a
    # PERSIST inside a MULTI so the live index never inherits an
    # expiration. This matches the pre-TTL behavior exactly.
    #
    # Empty rebuilds (no temp key) intentionally DEL final_key so the
    # live index reflects the empty result set. In that branch readers
    # can observe final_key as absent -- this is the correct outcome for
    # an index with zero members, not a transient gap.
    #
    # @param temp_key [String] The temporary key containing rebuilt index
    # @param final_key [String] The live index key
    # @param redis [Redis] The Redis connection
    # @param preserve_for [Integer] Seconds to retain temp_key after a
    #   failed swap, for diagnostics
    #
    def self.atomic_swap(temp_key, final_key, redis, preserve_for: DEFAULT_PRESERVE_TTL)
      # Check if temp key exists first - RENAME fails on non-existent keys.
      # redis.exists returns Integer across all supported redis-rb versions;
      # using > 0 also tolerates a future boolean return without breaking.
      unless redis.exists(temp_key) > 0
        Familia.info "[AtomicOp] No temp key to swap (empty result set)"
        # Empty rebuild: remove the live index so reads reflect zero members.
        # This is the one path where readers can legitimately see final_key
        # as absent -- the index genuinely has no entries.
        redis.del(final_key)
        return
      end

      # RENAME atomically replaces final_key if it exists (Redis >= 2.6),
      # so readers never observe a missing final_key during a non-empty
      # swap. A preceding DEL would open a gap where concurrent HGETs
      # return nil. PERSIST rides along in the same MULTI so the rebuilt
      # index does not inherit the temp key's rebuild-window TTL.
      begin
        raw = redis.multi do |tx|
          tx.rename(temp_key, final_key)
          tx.persist(final_key)
        end
        result = Familia::MultiResult.new(raw)

        # redis-rb 5.x raises on a failed command inside MULTI, but the
        # protocol returns it as an error object in the results array and
        # other clients/versions surface it that way (see MultiResult). A
        # failed RENAME with a "successful" return would leave the stale
        # index live while the caller reported success -- fail closed.
        raise result.errors.first if result.errors?
        raise Familia::Problem, "Atomic swap transaction aborted: #{temp_key} -> #{final_key}" unless result.successful?
      rescue Redis::CommandError => e
        # The temp key existed at the EXISTS check above, so "no such key"
        # here means it was evicted/expired/swept mid-swap: the rebuild is
        # lost and the live index is stale. Raise -- reporting success would
        # be the fail-open bug. There is nothing left to preserve.
        if e.message.include?('no such key')
          Familia.warn "[AtomicOp] Temp key #{temp_key} vanished during swap; index NOT updated"
          raise
        end

        # For other errors, retain the temp key for a bounded diagnostic
        # window instead of leaking a full index-sized key indefinitely.
        Familia.warn "[AtomicOp] Atomic swap failed: #{e.message}"
        begin
          redis.expire(temp_key, preserve_for)
          Familia.warn "[AtomicOp] Temp key #{temp_key} preserved for #{preserve_for}s"
        rescue StandardError => expire_error
          Familia.warn "[AtomicOp] Could not bound temp key #{temp_key}: #{expire_error.message}"
        end

        raise
      end

      Familia.info "[AtomicOp] Atomic swap completed: #{temp_key} -> #{final_key}"
    end

    # Deletes orphaned rebuild temp keys left behind by crashed processes.
    #
    # A key is deleted only when all of the following hold:
    #   - its suffix matches the current or legacy temp key shape
    #   - its TTL is -1 (no expiry, so it will never clean itself up)
    #   - its embedded timestamp is older than +older_than+ seconds
    #
    # Lock keys ("<final_key>:rebuild-lock") never match the pattern or the
    # suffix regex, so they are never touched.
    #
    # No in-library caller: this is an operator tool, meant to be run once
    # after upgrading to clear pre-upgrade leftovers (see the indexing guide).
    #
    # @param redis [Redis] The connection to sweep
    # @param pattern [String] SCAN MATCH pattern
    # @param older_than [Integer] Minimum age in seconds
    # @param dry_run [Boolean] When true, report without deleting
    # @return [Array<String>] Keys deleted (or that would be deleted)
    #
    def self.sweep_orphaned_temp_keys(redis, pattern: '*:rebuild:*', older_than: DEFAULT_PRESERVE_TTL,
                                      dry_run: false)
      cutoff = Familia.now.to_i - older_than
      swept = []

      redis.scan_each(match: pattern) do |key|
        match = TEMP_KEY_SUFFIX_PATTERN.match(key)
        next unless match
        # A live rebuild's temp key has no TTL between the HSET that creates
        # it and the first touch (and legacy keys never get one). Deleting it
        # would make the owner's swap take the empty branch and DEL the live
        # index, so a present lock on the base key vetoes the sweep.
        next if redis.exists(rebuild_lock_key(match.pre_match)).positive?
        # A TTL means the owning rebuild is alive (or the key is already on
        # a bounded diagnostic window); either way it cleans itself up.
        next unless redis.ttl(key) == -1
        next unless match[1].to_i < cutoff

        swept << key
      end

      swept.each_slice(500) { |chunk| redis.del(*chunk) } unless dry_run
      swept
    end
  end
end
