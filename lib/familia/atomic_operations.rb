# lib/familia/atomic_operations.rb
#
# frozen_string_literal: true

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
  # The canonical pattern:
  # 1. Build replacement contents in a temporary key (see {.build_temp_key}).
  # 2. Atomically swap it into place with {.atomic_swap}.
  #
  # All methods are module_function-style; call them directly on the module.
  #
  # @example Atomic index rebuild
  #   temp_key = Familia::AtomicOperations.build_temp_key(final_key)
  #   # ... populate temp_key ...
  #   Familia::AtomicOperations.atomic_swap(temp_key, final_key, redis)
  #
  module AtomicOperations
    # Builds a temporary key name for atomic swaps
    #
    # @param base_key [String] The final index key
    # @return [String] Temporary key with timestamp suffix
    #
    def self.build_temp_key(base_key)
      timestamp = Familia.now.to_i
      "#{base_key}:rebuild:#{timestamp}"
    end

    # Performs atomic swap of temp key to final key.
    #
    # Non-empty rebuilds use Redis RENAME (>= 2.6), which atomically
    # replaces final_key if it exists. Readers observe either the old
    # index or the new one; there is no window in which final_key is
    # absent. This avoids the partial-update, race-condition, and
    # stale-visibility problems of a two-step DEL+RENAME sequence.
    #
    # Empty rebuilds (no temp key) intentionally DEL final_key so the
    # live index reflects the empty result set. In that branch readers
    # can observe final_key as absent -- this is the correct outcome for
    # an index with zero members, not a transient gap.
    #
    # @param temp_key [String] The temporary key containing rebuilt index
    # @param final_key [String] The live index key
    # @param redis [Redis] The Redis connection
    #
    def self.atomic_swap(temp_key, final_key, redis)
      # Check if temp key exists first - RENAME fails on non-existent keys.
      # redis.exists returns Integer across all supported redis-rb versions;
      # using > 0 also tolerates a future boolean return without breaking.
      unless redis.exists(temp_key) > 0
        Familia.info "[Rebuild] No temp key to swap (empty result set)"
        # Empty rebuild: remove the live index so reads reflect zero members.
        # This is the one path where readers can legitimately see final_key
        # as absent -- the index genuinely has no entries.
        redis.del(final_key)
        return
      end

      # RENAME atomically replaces final_key if it exists (Redis >= 2.6),
      # so readers never observe a missing final_key during a non-empty
      # swap. A preceding DEL would open a gap where concurrent HGETs
      # return nil.
      redis.rename(temp_key, final_key)
      Familia.info "[Rebuild] Atomic swap completed: #{temp_key} -> #{final_key}"
    rescue Redis::CommandError => e
      # If temp key doesn't exist, just log and return (already handled above)
      if e.message.include?("no such key")
        Familia.info "[Rebuild] Temp key vanished during swap (concurrent operation?)"
        return
      end

      # For other errors, preserve temp key for debugging
      Familia.warn "[Rebuild] Atomic swap failed: #{e.message}"
      Familia.warn "[Rebuild] Temp key preserved for debugging: #{temp_key}"
      raise
    end
  end
end
