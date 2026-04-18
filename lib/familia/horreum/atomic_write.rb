# lib/familia/horreum/atomic_write.rb
#
# frozen_string_literal: true

module Familia
  class Horreum
    # AtomicWrite - Wraps scalar field persistence and collection mutations in a
    # single MULTI/EXEC transaction.
    #
    # Unlike {Persistence#save_with_collections}, which sequences two separate
    # writes (scalars first, then block), +atomic_write+ composes Familia's
    # existing +transaction+ infrastructure so every command -- the HMSET for
    # scalar fields, the expiration/index/instances bookkeeping, and all
    # collection mutations executed inside the block -- lands in one atomic
    # MULTI/EXEC. This is made possible by the fact that +DataType#dbclient+
    # already reads +Fiber[:familia_transaction]+ when set, so any call to
    # +plan.features.add(...)+ inside the block transparently routes its
    # command to the open transaction connection.
    #
    # Because MULTI/EXEC cannot span multiple Redis databases, a pre-flight
    # guard (+guard_atomic_write_database!+) rejects any configuration where
    # a related field declares a +logical_database+ that differs from the
    # parent Horreum's. In that case callers should fall back to
    # {Persistence#save_with_collections}.
    #
    # See issue #220 for the design rationale.
    #
    module AtomicWrite
      # Module-level mutex guarding the per-instance owner CAS. Held only for
      # the ivar read/write pairs that compose the re-entrancy check, so
      # contention is negligible even with many concurrent instances.
      OWNER_STATE_MUTEX = Mutex.new

      # Persists scalar fields and collection operations atomically in a single
      # MULTI/EXEC transaction.
      #
      # Scalar field assignments inside the block only mutate in-memory state
      # (deferred writes); the HMSET is issued by {#persist_to_storage} inside
      # the transaction. Collection mutations (e.g. +plan.features.add+) execute
      # immediately against the open transaction connection because
      # +DataType#dbclient+ honours +Fiber[:familia_transaction]+.
      #
      # Unique index validation (+prepare_for_save+) runs OUTSIDE the
      # transaction so it can perform the reads it needs. Only the writes
      # are atomic; the read-validate-write is not.
      #
      # @param update_expiration [Boolean] Whether to set TTL inside the txn.
      # @yield Block containing field assignments and collection mutations.
      # @return [Boolean] true if the transaction's EXEC completed and every
      #   queued command returned without an exception; false if the
      #   transaction was discarded or any queued command returned an error.
      # @raise [ArgumentError] If no block is given.
      # @raise [Familia::OperationModeError] If called within an existing transaction.
      # @raise [Familia::CrossDatabaseError] If related fields span multiple databases.
      # @raise [Familia::NoIdentifier] If the identifier is nil or empty.
      #
      # @example Atomically update scalar fields and a set
      #   plan.atomic_write do
      #     plan.name = "Premium"
      #     plan.region = "US"
      #     plan.features.clear
      #     plan.features.add("sso")
      #   end
      #
      # @see Persistence#save_with_collections For sequential (non-atomic)
      #   scalar+collection writes (supports cross-database configurations).
      # @see Connection#transaction For raw MULTI/EXEC access.
      #
      def atomic_write(update_expiration: true)
        raise ArgumentError, 'Block required for atomic_write' unless block_given?

        # Mirror save's nesting guard -- atomic_write opens its own MULTI and
        # cannot be nested inside an outer transaction (see Persistence#save).
        if Fiber[:familia_transaction]
          raise Familia::OperationModeError, <<~ERROR_MESSAGE
            Cannot call atomic_write within an existing transaction. atomic_write opens its own MULTI/EXEC and cannot be nested.
          ERROR_MESSAGE
        end

        # Same-instance re-entrancy guard. The Fiber[:familia_transaction]
        # check is Fiber-local, so it only protects re-entry within the same
        # Fiber. A second Fiber or Thread touching the same Horreum instance
        # would otherwise open a parallel MULTI against shared scalar state
        # and race HMSET -- defeating the "atomic" contract. The check-then-
        # set on @atomic_write_owner is serialised under OWNER_STATE_MUTEX so
        # two threads can't both observe a nil owner and simultaneously claim
        # ownership.
        acquire_atomic_write_ownership!

        begin
          guard_atomic_write_database!

          # prepare_for_save must run OUTSIDE the transaction: guard_unique_indexes!
          # performs reads, which return uninspectable Redis::Future objects inside
          # MULTI/EXEC.
          prepare_for_save

          result = transaction do |_conn|
            # Yield FIRST so scalar setters mutate ivars and collection mutations
            # queue their commands (SADD, ZADD, etc.) in the open MULTI.
            # Collection mutations auto-route via Fiber[:familia_transaction]
            # (see DataType#dbclient).
            yield

            # Then queue the HMSET for scalar fields. to_h_for_storage snapshots
            # ivars at command-queue time, so any assignments made inside the
            # block are captured. Also queues expiration, class indexes, and
            # touch_instances!.
            persist_to_storage(update_expiration)
          end

          # A MultiResult is always returned by `transaction` -- inspect its
          # successful? flag rather than testing for nil. Individual commands
          # inside MULTI return exception objects (rather than raising) when
          # they fail; successful? is false if any of those slipped through.
          success = atomic_write_success?(result)
          clear_dirty! if success
          success
        ensure
          release_atomic_write_ownership!
        end
      end

      # Returns true while inside an {#atomic_write} block.
      #
      # Consulted by +Familia::DataType#warn_if_dirty!+ to suppress the
      # dirty-state warning for collection mutations that legitimately run
      # against dirty in-memory scalars inside an atomic_write block (the
      # scalars will be persisted by the same transaction).
      #
      # This predicate is intended to be queried from the same Fiber/Thread
      # that owns the active atomic_write block. The +@atomic_write_active+
      # ivar is read without the +OWNER_STATE_MUTEX+ that guards
      # {#acquire_atomic_write_ownership!}, so a query issued from a
      # different Fiber or Thread is advisory and may observe stale state
      # (either a +true+ that has just been cleared, or a +false+ that has
      # just been set). This is by design: the sole intended caller --
      # +Familia::DataType#warn_if_dirty!+ -- runs from the same Fiber that
      # invoked +atomic_write+, so the read is always consistent in the
      # cases that matter. Adding a lock on every collection mutation purely
      # to make a single advisory log line precise across Fibers/Threads
      # would be the wrong tradeoff.
      #
      # @return [Boolean]
      #
      def atomic_write_mode?
        @atomic_write_active == true
      end

      private

      # Atomically claim same-instance ownership or raise if a competing
      # Fiber/Thread already owns it. Held for the duration of the ivar
      # check-then-set only.
      #
      # @raise [Familia::OperationModeError]
      # @return [void]
      def acquire_atomic_write_ownership!
        OWNER_STATE_MUTEX.synchronize do
          if @atomic_write_owner && @atomic_write_owner != Fiber.current
            raise Familia::OperationModeError, <<~ERROR_MESSAGE
              atomic_write is already active on this instance in another Fiber or Thread. Concurrent atomic_write on the same instance is not supported.
            ERROR_MESSAGE
          end

          @atomic_write_owner = Fiber.current
          @atomic_write_active = true
        end
      end

      # Release same-instance ownership. Safe to call in an ensure block even
      # if acquire_atomic_write_ownership! raised before assigning.
      #
      # @return [void]
      def release_atomic_write_ownership!
        OWNER_STATE_MUTEX.synchronize do
          @atomic_write_active = false
          @atomic_write_owner = nil
        end
      end

      # Determine whether the transaction committed cleanly. MultiResult
      # wraps the command return values; any Exception object among those
      # values flips successful? to false (see MultiResult#successful?).
      # A nil result covers the rare case where the driver returns no
      # MultiResult at all (e.g. transaction discarded).
      #
      # @param result [MultiResult, nil]
      # @return [Boolean]
      def atomic_write_success?(result)
        return false if result.nil?
        return result.successful? if result.is_a?(MultiResult)

        true
      end

      # Pre-flight check for atomic_write: every related DataType field must
      # share the same +logical_database+ as this Horreum, because MULTI/EXEC
      # cannot span multiple Redis databases.
      #
      # Both instance-level related fields (+related_fields+) and class-level
      # related fields (+class_related_fields+) are inspected. Class-level
      # collections matter because +persist_to_storage+ calls
      # +touch_instances!+, which writes to +self.class.instances+ (a
      # class-level sorted set) inside the same MULTI; a mismatched database
      # there would silently route commands to the wrong connection.
      #
      # A +nil+ value on a related field's +logical_database+ option means
      # "inherit from parent" and is always safe: the DataType instance
      # resolves its connection via +opts[:parent]+, which is either this
      # Horreum (instance-level) or the Horreum class itself (class-level),
      # so the effective database always matches +horreum_db+.
      #
      # +horreum_db+ is resolved to a concrete integer so that an explicit
      # +logical_database: 0+ on a related field does not falsely trigger the
      # guard when the Horreum has not set +logical_database+ itself and
      # would otherwise inherit from +Familia.logical_database+ (also 0 by
      # default).
      #
      # @raise [Familia::CrossDatabaseError] if any related field declares a
      #   different +logical_database+ than the parent Horreum.
      # @return [void]
      #
      def guard_atomic_write_database!
        horreum_db = self.class.logical_database || Familia.logical_database || 0

        [self.class.related_fields, self.class.class_related_fields].each do |registry|
          registry.each do |field_name, definition|
            field_db = definition.opts[:logical_database]
            next if field_db.nil?
            next if field_db == horreum_db

            raise Familia::CrossDatabaseError.new(field_name, field_db, horreum_db)
          end
        end
      end
    end
  end
end
