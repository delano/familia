# lib/familia/connection/operations.rb
#
# frozen_string_literal: true

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  module Connection
    module Operations
      # Executes Database commands atomically within a transaction (MULTI/EXEC).
      #
      # Database transactions queue commands and execute them atomically as a single unit.
      # All commands succeed together or all fail together, ensuring data consistency.
      #
      # @yield [Redis] The Database transaction connection
      # @return [Array] Results of all commands executed in the transaction
      #
      # @example Basic transaction usage
      #   Familia.transaction do |trans|
      #     trans.set("key1", "value1")
      #     trans.incr("counter")
      #     trans.lpush("list", "item")
      #   end
      #   # Returns: ["OK", 2, 1] - results of all commands
      #
      # @note **Comparison of Database batch operations:**
      #
      #   | Feature         | Multi/Exec      | Pipeline        |
      #   |-----------------|-----------------|-----------------|
      #   | Atomicity       | Yes             | No              |
      #   | Performance     | Good            | Better          |
      #   | Error handling  | All-or-nothing  | Per-command     |
      #   | Use case        | Data consistency| Bulk operations |
      #
      # Executes a Redis transaction (MULTI/EXEC) with proper connection handling.
      #
      # Provides atomic execution of multiple Redis commands with automatic connection
      # management and operation mode enforcement. Returns a MultiResult object containing
      # both success status and command results.
      #
      # @param [Proc] block The block containing Redis commands to execute atomically
      # @yield [Redis] conn The Redis connection configured for transaction mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #   (e.g., FiberConnectionHandler or DefaultConnectionHandler that don't support transactions)
      #
      # @example Basic transaction usage
      #   result = Familia.transaction do |conn|
      #     conn.set('key1', 'value1')
      #     conn.set('key2', 'value2')
      #     conn.get('key1')
      #   end
      #   result.successful?    # => true (if all commands succeeded)
      #   result.results        # => ["OK", "OK", "value1"]
      #   result.results.first  # => "OK"
      #
      # @example Checking transaction success
      #   result = Familia.transaction do |conn|
      #     conn.incr('counter')
      #     conn.decr('other_counter')
      #   end
      #
      #   if result.successful?
      #     puts "All commands succeeded: #{result.results}"
      #   else
      #     puts "Some commands failed: #{result.results}"
      #   end
      #
      # @example Nested transactions (reentrant behavior)
      #   result = Familia.transaction do |outer_conn|
      #     outer_conn.set('outer', 'value')
      #
      #     # Nested transaction reuses the same connection
      #     inner_result = Familia.transaction do |inner_conn|
      #       inner_conn.set('inner', 'value')
      #       inner_conn.get('inner')  # Returns the value directly in nested context
      #     end
      #
      #     [outer_result, inner_result]
      #   end
      #
      # @note Connection Handler Compatibility:
      #   - FiberTransactionHandler: Supports reentrant transactions
      #   - ProviderConnectionHandler: Full transaction support
      #   - CreateConnectionHandler: Full transaction support
      #   - FiberConnectionHandler: Blocked (raises OperationModeError)
      #   - DefaultConnectionHandler: Blocked (raises OperationModeError)
      #
      # @note Thread Safety:
      #   Uses Fiber-local storage to maintain transaction context across nested calls
      #   and ensure proper cleanup even when exceptions occur.
      #
      # @see MultiResult For details on the return value structure
      # @see Familia.pipelined For non-atomic command batching
      # @see #multi_field_update For similar MultiResult pattern in Horreum models
      def transaction(&)
        Familia::Connection::TransactionCore.execute_transaction(-> { dbclient }, &)
      end
      alias multi transaction

      # Persists multiple Horreum instances in a SINGLE MULTI/EXEC transaction.
      #
      # This is the cross-model / multi-instance counterpart to
      # {Familia::Horreum::AtomicWrite#atomic_write}. Where the instance method
      # composes one object's scalar HMSET and collection mutations into one
      # transaction, this module-level method folds the persistence of several
      # (possibly different-class) instances into one atomic MULTI/EXEC.
      #
      # ## Why this works
      #
      # Once a MULTI opens, every instance's +dbclient+ resolves to the same
      # +Fiber[:familia_transaction]+ connection. So the HMSET, EXPIRE, index
      # HSET, and instances ZADD for each instance all queue on one socket and
      # commit together. The transaction is anchored on
      # +instances.first.dbclient+; because {#guard_cross_model_database!}
      # enforces that all roots share ONE logical database, every instance
      # routes to that same connection -- there is no special routing to
      # engineer, the same-logical-DB requirement IS the constraint.
      #
      # ## Read/write split
      #
      # The read-validate-write split is the key constraint. +prepare_for_save+
      # (timestamps + unique-index reads) runs OUTSIDE the transaction because
      # the reads it performs would return uninspectable +Redis::Future+ objects
      # inside MULTI/EXEC. Only +persist_to_storage+ (HMSET/EXPIRE/index
      # HSET/instances ZADD -- write-only) runs INSIDE.
      #
      # ## Optimistic locking / create-only
      #
      # Pass +watch_keys:+ to wrap the MULTI in a WATCH block, and +pre_check:+
      # to run a guard between WATCH and MULTI (the only window where reads
      # return real values while the watched keys are guarded). A concurrent
      # modification of any watched key aborts EXEC and retries (the committed
      # primitive owns abort detection + retry). This enables a race-safe
      # create-only pattern -- see the example below.
      #
      # @param instances [Array<Familia::Horreum>] One or more instances to persist.
      # @param update_expiration [Boolean] Whether to set each instance's TTL
      #   inside the transaction (default: true).
      # @param watch_keys [Array<String>, nil] Optional keys to WATCH before
      #   opening the MULTI. When present, the transaction retries on WATCH abort.
      # @param pre_check [Proc, nil] Optional callable executed between WATCH and
      #   MULTI. Requires +watch_keys+. Typically raises to abort early (e.g.
      #   existence checks for create-only semantics).
      # @yield Optional user block run inside the transaction BEFORE each
      #   instance is persisted -- the place to assign cross-references between
      #   instances (e.g. +org.owner_id = customer.identifier+) and mutate
      #   collections.
      # @return [Boolean] true if the MULTI/EXEC committed cleanly; false if the
      #   transaction was discarded or any queued command returned an error.
      #
      # @raise [ArgumentError] If no instances are given, or +pre_check+ is
      #   provided without +watch_keys+.
      # @raise [Familia::OperationModeError] If called within an existing transaction.
      # @raise [Familia::CrossDatabaseError] If the roots (or their related
      #   fields) span multiple logical databases.
      # @raise [Familia::OptimisticLockError] If +watch_keys+ retries are exhausted.
      #
      # @example Persist two models atomically
      #   Familia.atomic_write(customer, org) do
      #     org.owner_id = customer.identifier
      #     customer.orgs.add(org.identifier)
      #   end
      #
      # @example Race-safe create-only (reject if EITHER key already exists)
      #   Familia.atomic_write(customer, org,
      #     watch_keys: [customer.dbkey, org.dbkey],
      #     pre_check: -> {
      #       [customer, org].each { |r| raise Familia::RecordExistsError, r.dbkey if r.exists? }
      #     }
      #   ) do
      #     customer.name = 'Acme Owner'
      #     org.owner_id = customer.identifier
      #   end
      #   # A concurrent creation of EITHER key during the WATCH window aborts the
      #   # whole MULTI and retries; on retry the existence check raises
      #   # RecordExistsError -- no silent overwrite.
      #
      # @note On Redis Cluster, a cross-model MULTI also requires the watched and
      #   written keys to share a hash slot (CROSSSLOT error otherwise).
      #   Co-locate related models with hash tags, e.g. +customer:{acct42}:object+.
      #
      # @note When +watch_keys+ is set and a WATCH abort triggers a retry, the
      #   user block AND each +persist_to_storage+ are re-executed on every
      #   attempt. The aborted MULTI discards all queued Redis commands, so Redis
      #   state is clean on retry, but side effects outside Redis (logging,
      #   counters, external API calls) in the user block fire again -- design
      #   retry-safe blocks when using +watch_keys+.
      #
      # @see Familia::Horreum::AtomicWrite#atomic_write Single-instance variant.
      #
      def atomic_write(*instances, update_expiration: true, watch_keys: nil, pre_check: nil, &user_block)
        raise ArgumentError, 'atomic_write requires at least one instance' if instances.empty?
        raise ArgumentError, 'pre_check requires watch_keys' if pre_check && !watch_keys&.any?
        if Fiber[:familia_transaction]
          raise Familia::OperationModeError,
                'Cannot call Familia.atomic_write within a transaction. It opens its own MULTI/EXEC and cannot be nested.'
        end

        guard_cross_model_database!(instances)        # all roots + their related fields share ONE logical db

        # Activate atomic_write mode on every instance BEFORE prepare_for_save so
        # that collection mutations in the user block do not trip dirty-write
        # warnings -- or, under :strict / raise_on_unsaved_parent_write, raises --
        # against the just-dirtied scalars. Those scalars are persisted by this
        # same MULTI, so the writes are legitimate. Mirrors the instance-level
        # atomic_write (which acquires ownership before prepare_for_save). Only the
        # instances actually acquired are released, in the ensure below.
        acquired = []
        begin
          instances.each do |i|
            i.send(:acquire_atomic_write_ownership!)
            acquired << i
          end

          instances.each { |i| i.send(:prepare_for_save) }   # READS — outside the txn

          persist_all = lambda do
            user_block&.call
            instances.each { |i| i.send(:persist_to_storage, update_expiration) }
          end

          result =
            if watch_keys&.any?
              Familia::Connection::TransactionCore.execute_watched_transaction(
                -> { instances.first.dbclient }, watch_keys: watch_keys
              ) do |conn|
                pre_check&.call
                Familia::Connection::TransactionCore.execute_normal_transaction(-> { conn }) { persist_all.call }
              end
            else
              # Route the non-watched path through the instance #transaction so it
              # inherits execute_transaction's handler-compatibility gate: a
              # connection whose handler disallows transactions falls back per
              # Familia.transaction_mode (raise/warn/individual) instead of
              # issuing a raw MULTI on an unsupported connection. (The watched
              # branch above must call execute_normal_transaction directly to
              # reuse the WATCH-resolved connection; this branch has no such
              # constraint.) Anchored on instances.first -- the guard ensures all
              # roots share one logical database, so it routes every instance.
              instances.first.transaction { persist_all.call }
            end

          success = result.is_a?(Familia::MultiResult) ? result.successful? : !result.nil?
          instances.each { |i| i.send(:clear_dirty!) } if success
          success
        ensure
          acquired.each { |i| i.send(:release_atomic_write_ownership!) }
        end
      end

      # Executes Database commands in a pipeline for improved performance.
      #
      # Pipelines send multiple commands without waiting for individual responses,
      # reducing network round-trips. Commands execute independently and can
      # succeed or fail without affecting other commands in the pipeline.
      #
      # @yield [Redis] The Database pipeline connection
      # @return [Array] Results of all commands executed in the pipeline
      #
      # @example Basic pipeline usage
      #   Familia.pipelined do |pipe|
      #     pipe.set("key1", "value1")
      #     pipe.incr("counter")
      #     pipe.lpush("list", "item")
      #   end
      #   # Returns: ["OK", 2, 1] - results of all commands
      #
      # @example Error handling - commands succeed/fail independently
      #   results = Familia.pipelined do |conn|
      #     conn.set("valid_key", "value")     # This will succeed
      #     conn.incr("string_key")            # This will fail (wrong type)
      #     conn.set("another_key", "value2")  # This will still succeed
      #   end
      #   # Returns: ["OK", Redis::CommandError, "OK"]
      #   # Notice how the error doesn't prevent other commands from executing
      #
      # @example Contrast with transaction behavior
      #   results = Familia.transaction do |conn|
      #     conn.set("inventory:item1", 100)
      #     conn.incr("invalid_key")        # Fails, rolls back everything
      #     conn.set("inventory:item2", 200) # Won't be applied
      #   end
      #   # Result: neither item1 nor item2 are set due to the error
      #
      # Executes Redis commands in a pipeline for improved performance.
      #
      # Batches multiple Redis commands together and sends them in a single network
      # round-trip, improving performance for multiple independent operations. Returns
      # a MultiResult object containing both success status and command results.
      #
      # @param [Proc] block The block containing Redis commands to execute in pipeline
      # @yield [Redis] conn The Redis connection configured for pipelined mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #   (e.g., FiberConnectionHandler or DefaultConnectionHandler that don't support pipelines)
      #
      # @example Basic pipeline usage
      #   result = Familia.pipelined do |conn|
      #     conn.set('key1', 'value1')
      #     conn.set('key2', 'value2')
      #     conn.get('key1')
      #     conn.incr('counter')
      #   end
      #   result.successful?    # => true (if all commands succeeded)
      #   result.results        # => ["OK", "OK", "value1", 1]
      #   result.results.length # => 4
      #
      # @example Performance optimization with pipeline
      #   # Instead of multiple round-trips:
      #   # value1 = redis.get('key1')  # Round-trip 1
      #   # value2 = redis.get('key2')  # Round-trip 2
      #   # value3 = redis.get('key3')  # Round-trip 3
      #
      #   # Use pipeline for single round-trip:
      #   result = Familia.pipelined do |conn|
      #     conn.get('key1')
      #     conn.get('key2')
      #     conn.get('key3')
      #   end
      #   values = result.results  # => ["value1", "value2", "value3"]
      #
      # @example Checking pipeline success
      #   result = Familia.pipelined do |conn|
      #     conn.set('temp_key', 'temp_value')
      #     conn.expire('temp_key', 60)
      #     conn.get('temp_key')
      #   end
      #
      #   if result.successful?
      #     puts "Pipeline completed: #{result.results}"
      #   else
      #     puts "Some operations failed: #{result.results}"
      #   end
      #
      # @example Nested pipelines (reentrant behavior)
      #   result = Familia.pipelined do |outer_conn|
      #     outer_conn.set('outer', 'value')
      #
      #     # Nested pipeline reuses the same connection
      #     inner_result = Familia.pipelined do |inner_conn|
      #       inner_conn.get('outer')  # Returns Redis::Future in nested context
      #     end
      #
      #     outer_conn.get('outer')
      #   end
      #
      # @note Pipeline vs Transaction Differences:
      #   - Pipeline: Commands executed independently, some may succeed while others fail
      #   - Transaction: All-or-nothing execution, commands are atomic as a group
      #   - Pipeline: Better performance for independent operations
      #   - Transaction: Better consistency for related operations
      #
      # @note Connection Handler Compatibility:
      #   - FiberPipelineHandler: Supports reentrant pipelines
      #   - ProviderConnectionHandler: Full pipeline support
      #   - CreateConnectionHandler: Full pipeline support
      #   - FiberTransactionHandler: Blocked (raises OperationModeError)
      #   - FiberConnectionHandler: Blocked (raises OperationModeError)
      #   - DefaultConnectionHandler: Blocked (raises OperationModeError)
      #
      # @note Thread Safety:
      #   Uses Fiber-local storage to maintain pipeline context across nested calls
      #   and ensure proper cleanup even when exceptions occur.
      #
      # @see MultiResult For details on the return value structure
      # @see Familia.transaction For atomic command execution
      # @see #multi_field_update For similar MultiResult pattern in Horreum models
      def pipelined(&)
        PipelineCore.execute_pipeline(-> { dbclient }, &)
      end
      alias pipeline pipelined

      # Provides explicit access to a Database connection.
      #
      # This method is useful when you need direct access to a connection
      # for operations not covered by other methods. The connection is
      # properly managed and returned to the pool (if using connection_provider).
      #
      # @yield [Redis] A Database connection
      # @return The result of the block
      #
      # @example Using with_dbclient for custom operations
      #   Familia.with_dbclient do |conn|
      #     conn.set("custom_key", "value")
      #     conn.expire("custom_key", 3600)
      #   end
      #
      def with_dbclient(&)
        yield dbclient
      end

      # Provides explicit access to an isolated Database connection for temporary operations.
      #
      # This method creates a new connection that won't interfere with the cached
      # connection pool, executes the given block with that connection, and ensures
      # the connection is properly closed afterward.
      #
      # Perfect for database scanning, inspection, or migration operations where
      # you need to access different databases without affecting your models'
      # normal connections.
      #
      # @param uri [String, URI, Integer, nil] The URI or database number to connect to.
      # @yield [Redis] An isolated Database connection
      # @return The result of the block
      #
      # @example Safely scanning for legacy data
      #   Familia.with_isolated_dbclient(5) do |conn|
      #     conn.keys("session:*")
      #   end
      #
      # @example Performing migration tasks
      #   Familia.with_isolated_dbclient(1) do |conn|
      #     conn.scan_each(match: "user:*") { |key| puts key }
      #   end
      #
      def with_isolated_dbclient(uri = nil, &)
        client = isolated_dbclient(uri)
        begin
          yield client
        ensure
          client&.close
        end
      end

      private

      # Pre-flight guard for {#atomic_write}: every root instance -- and, by
      # transitivity, every related field on every root -- must resolve to the
      # SAME logical database. MULTI/EXEC cannot span databases, so anchoring the
      # transaction on +instances.first.dbclient+ is only correct when all roots
      # share that database.
      #
      # Two layers of checking:
      #
      # 1. Compare each root's resolved logical database (+klass.logical_database+
      #    falling back to +Familia.logical_database || 0+). If they differ, the
      #    roots span databases and a synthetic "(root)" {Familia::CrossDatabaseError}
      #    is raised before any write.
      #
      # 2. Reuse each instance's existing per-instance field guard
      #    (+guard_atomic_write_database!+), which checks that instance's
      #    +related_fields+ and +class_related_fields+ against its own database.
      #    Because step 1 proved all instance databases are equal, this
      #    transitively proves every field across every root shares the one
      #    database.
      #
      # @param instances [Array<Familia::Horreum>]
      # @raise [Familia::CrossDatabaseError] if roots span databases, or any
      #   instance has a related field on a different database.
      # @return [void]
      #
      def guard_cross_model_database!(instances)
        dbs = instances.map { |i| i.class.logical_database || Familia.logical_database || 0 }
        unless dbs.uniq.size == 1
          # roots span databases — MULTI/EXEC cannot cross databases
          offender_idx = dbs.index { |d| d != dbs.first }
          offender = instances[offender_idx]
          raise Familia::CrossDatabaseError.new(
            "#{offender.class} (root)", dbs[offender_idx], dbs.first
          )
        end
        # Reuse each instance's existing per-instance field guard (related_fields +
        # class_related_fields vs that instance's own db). Since all instance dbs are
        # equal, this transitively proves every field shares the one db.
        instances.each { |i| i.send(:guard_atomic_write_database!) }
      end
    end
  end
end
