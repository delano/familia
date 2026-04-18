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
      # @return [Boolean] true if the transaction committed successfully.
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

        guard_atomic_write_database!

        @atomic_write_active = true
        begin
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

          clear_dirty! unless result.nil?
          !result.nil?
        ensure
          @atomic_write_active = false
        end
      end

      # Returns true while inside an {#atomic_write} block.
      #
      # Consulted by +Familia::DataType#warn_if_dirty!+ to suppress the
      # dirty-state warning for collection mutations that legitimately run
      # against dirty in-memory scalars inside an atomic_write block (the
      # scalars will be persisted by the same transaction).
      #
      # @return [Boolean]
      #
      def atomic_write_mode?
        @atomic_write_active == true
      end

      private

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
      # "inherit from parent" and is always safe.
      #
      # @raise [Familia::CrossDatabaseError] if any related field declares a
      #   different +logical_database+ than the parent Horreum.
      # @return [void]
      #
      def guard_atomic_write_database!
        horreum_db = self.class.logical_database

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
