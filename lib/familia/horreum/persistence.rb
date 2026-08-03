# lib/familia/horreum/persistence.rb
#
# frozen_string_literal: true

module Familia
  # Familia::Horreum
  #
  # Core persistence class for object-relational mapping with Valkey/Redis.
  # Provides serialization, field management, and database interaction capabilities.
  #
  class Horreum
    # Valid return values from database commands
    #
    # Defines the set of acceptable response values that indicate successful
    # command execution in Valkey operations. These values are used to validate
    # database responses and determine operation success.
    #
    # @return [Array<String, Boolean, Integer, nil>] Frozen array of valid return values:
    #   - "OK" - Standard success response for most commands
    #   - true - Boolean success indicator
    #   - 1 - Numeric success indicator (operation performed)
    #   - 0 - Numeric indicator (operation attempted, no change needed)
    #   - nil - Valid response for certain operations
    #
    # @example Validating a command response
    #   response = dbclient.set("key", "value")
    #   valid = @valid_command_return_values.include?(response)
    #   # => true if response is "OK"
    #
    @valid_command_return_values = ['OK', true, 1, 0, nil].freeze

    class << self
      attr_reader :valid_command_return_values
    end

    # Serialization - Instance-level methods for object persistence and retrieval
    # Handles conversion between Ruby objects and Valkey hash storage
    #
    module Persistence
      # Persists object state to storage with timestamps, validation, and indexing.
      #
      # Performs a complete save operation in an atomic transaction:
      # - Sets created/updated timestamps
      # - Validates unique index constraints
      # - Persists all fields
      # - Updates expiration (optional)
      # - Updates class-level indexes
      # - Adds to instances collection
      #
      # ## Transaction Safety
      #
      # This method CANNOT be called within a transaction context. The save process
      # requires reading current state to validate unique constraints, which would
      # return uninspectable Redis::Future objects inside transactions.
      #
      # ### Correct Pattern:
      #     customer = Customer.new(email: 'test@example.com')
      #     customer.save  # Validates unique constraints here
      #
      #     customer.transaction do
      #       # Perform other atomic operations
      #       customer.increment(:login_count)
      #       customer.hset(:last_login, Familia.now.to_i)
      #     end
      #
      # ### Incorrect Pattern:
      #     Customer.transaction do
      #       customer = Customer.new(email: 'test@example.com')
      #       customer.save  # Raises Familia::OperationModeError
      #     end
      #
      # @param update_expiration [Boolean] Whether to refresh key expiration (default: true)
      # @return [Boolean] true on success
      #
      # @raise [Familia::OperationModeError] If called within a transaction
      # @raise [Familia::RecordExistsError] If unique index constraint violated
      #
      # @example Basic usage
      #   user = User.new(email: "john@example.com")
      #   user.save  # => true
      #
      # @example Post-save callback (idiomatic Ruby)
      #   if user.save
      #     AuditLog.record(:user_updated, user.identifier)
      #     notify(user)
      #   end
      #
      # @example Single-expression short-circuit
      #   user.save && AuditLog.record(:user_updated, user.identifier)
      #
      # @note This is a FULL-OVERWRITE of the object's scalar state: afterwards
      #   the stored hash matches the in-memory object exactly. Non-nil fields are
      #   written and fields that are nil in memory are removed from storage. A
      #   field managed out of band -- e.g. one claimed by another actor via
      #   HSETNX while this (possibly stale) copy still holds nil for it -- is
      #   therefore cleared by a full save. To update an object without disturbing
      #   such fields, use the targeted writers ({#save_fields},
      #   {#multi_field_update}, {#multi_field_fast_write}) or {#refresh!} first.
      #
      # @see #save_if_not_exists! For conditional saves
      # @see #transaction For atomic operations after save
      #
      def save(update_expiration: true)
        start_time = Familia.now_in_μs if Familia.debug?

        # Prevent save within transaction - unique index guards require read operations
        # which are not available in Redis MULTI/EXEC blocks
        if Fiber[:familia_transaction]
          raise Familia::OperationModeError, <<~ERROR_MESSAGE
            Cannot call save within a transaction. Save operations must be called outside transactions to ensure unique constraints can be validated.
          ERROR_MESSAGE
        end

        Familia.trace :SAVE, nil, self.class.uri if Familia.debug?

        # Prepare object for persistence (timestamps, validation)
        prepare_for_save

        # Pre-read the instance-scoped index tracker before MULTI/EXEC, for
        # the same reason destroy! does: HGETALL inside a transaction returns
        # futures, not values. Replayed inside the transaction below, where
        # dirty tracking is still live (see #auto_update_class_indexes).
        tracked_scopes = if respond_to?(:read_instance_index_scopes)
          read_instance_index_scopes
        else
          {}
        end

        # A non-empty tracker with no object hash can only belong to a dead
        # incarnation of this identifier: add_to_* refuses never-saved
        # records, so entries outliving the hash mean delete! (or expiry)
        # removed the hash out from under them. Replaying them would silently
        # re-join whatever scopes the PREVIOUS record occupied (#365), so the
        # transaction below prunes them instead -- replaying remove_from_*
        # with the recorded values, which also clears the index entries the
        # dead incarnation left behind. The EXISTS probe costs a round trip
        # only when the tracker has entries.
        #
        # The probe runs before the MULTI, so a concurrent delete! landing
        # between the two makes a live tracker look stale and the save prunes
        # memberships that were valid an instant earlier. That is the
        # accepted conservative failure mode -- losing memberships for a
        # record that was just deleted beats joining the wrong scopes -- and
        # the same read-window race save already accepts for its guards
        # (MULTI-only by design, no WATCH).
        stale_tracker = !tracked_scopes.empty? && !exists?

        # Validate instance-scoped unique constraints here too -- same reason
        # prepare_for_save runs guard_unique_indexes! outside the transaction
        # (the guard reads). guard_unique_indexes! only covers class-level
        # relationships; without this, the refresh below could evict another
        # record's index entry silently. Stale entries are pruned rather than
        # replayed, so there is no membership to validate.
        if !stale_tracker && respond_to?(:guard_tracked_index_scopes!)
          guard_tracked_index_scopes!(tracked_scopes)
        end

        # Everything in ONE transaction for complete atomicity
        result = transaction do |_conn|
          persist_to_storage(update_expiration, tracked_index_scopes: tracked_scopes,
                                                prune_stale_tracker: stale_tracker)
        end

        # Structured lifecycle logging and instrumentation
        if Familia.debug? && start_time
          duration = Familia.now_in_μs - start_time

          begin
            fields_count = to_h_for_storage.size
          rescue StandardError => e
            Familia.error 'Failed to serialize fields for logging',
              error: e.message,
              class: self.class.name,
              identifier: begin
                identifier
              rescue StandardError
                nil
              end
            fields_count = 0
          end

          Familia.debug 'Horreum saved',
            class: self.class.name,
            identifier: identifier,
            duration: duration,
            fields_count: fields_count,
            update_expiration: update_expiration

          Familia::Instrumentation.notify_lifecycle(:save, self,
            duration: duration,
            update_expiration: update_expiration,
            fields_count: fields_count)
        end

        # Clear dirty tracking after successful save
        clear_dirty! if persisted_successfully?(result)

        # Return boolean indicating success
        persisted_successfully?(result)
      end

      # Saves scalar fields first, then executes collection operations in the block.
      #
      # This method enforces the ordering invariant that scalar fields (stored
      # in the object's hash key via HMSET) are committed before any collection
      # operations (SADD, ZADD, RPUSH, etc.) run. If +save+ raises, the block
      # is never executed, preventing orphaned collection data.
      #
      # Because scalar fields and collection fields typically live on different
      # Redis keys, they cannot share a single MULTI/EXEC transaction. This
      # method provides a safe sequential alternative: scalars commit first,
      # then collections execute. If a collection operation fails after save
      # succeeds, the scalar data remains persisted (no automatic rollback of
      # the save).
      #
      # @param update_expiration [Boolean] Passed through to +save+ (default: true)
      # @yield Block containing collection operations to execute after save
      # @return [Boolean] true if save succeeded and block completed
      #
      # @raise [Familia::OperationModeError] If called within a transaction
      # @raise [Familia::RecordExistsError] If unique index constraint violated
      #
      # @example Save a plan then update its feature set
      #   plan.name = 'Premium'
      #   plan.save_with_collections do
      #     plan.features.clear
      #     plan.features.add('premium')
      #     plan.features.add('priority_support')
      #   end
      #
      # @example Block is skipped when save fails
      #   plan.save_with_collections do
      #     plan.features.add('premium')  # never runs if save raises
      #   end
      #
      # @see #save For the underlying scalar persistence
      # @see #transaction For atomic operations on same-key commands
      # @see #atomic_write For true MULTI/EXEC atomicity spanning scalars and
      #   collections (single-database only).
      #
      def save_with_collections(update_expiration: true)
        saved = save(update_expiration: update_expiration)
        yield if saved && block_given?
        saved
      end

      # Conditionally persists object only if it doesn't already exist in storage.
      #
      # Uses optimistic locking (WATCH + MULTI/EXEC on a single connection) to
      # guard the existence check against the save. If the object doesn't exist,
      # performs identical operations as save. If it exists, raises an error;
      # concurrent modification of the watched key aborts EXEC and retries.
      #
      # `save_if_not_exists` doesn't call save because of the gap between checking
      # existence and persisting the data. We can't check for existence inside the
      # transaction because commands are queued and not executed until EXEC
      # is called (if you try you get a Redis::Future object). So here we use a
      # WATCH + MULTI/EXEC pattern to fail the transaction if the key is created
      # (or modified in any way) between the check and EXEC, avoiding silent data
      # corruption♀︎. The WATCH and the MULTI/EXEC run on the SAME resolved
      # connection (see TransactionCore.execute_watched_transaction) -- this is
      # what makes the optimistic lock effective; split across connections it
      # would be inert.

      # ♀︎ Additional note about WATCH + MULTI/EXEC in Valkey/Redis or any two
      # step existence check in any database: although it is more cautious and,
      # on a single connection, a genuine optimistic lock (a concurrent write to
      # the watched key aborts EXEC), it is still not a server-side atomic check.
      # The only way to do that is if the database process can determine itself
      # whether the record already exists or not. For Valkey/Redis, that means
      # writing the lua to do that.
      #
      # @param update_expiration [Boolean] Whether to refresh key expiration (default: true)
      # @return [Boolean] true on successful save
      #
      # @raise [Familia::RecordExistsError] If object already exists
      # @raise [Familia::OptimisticLockError] If retries exhausted (max 3 attempts)
      # @raise [Familia::OperationModeError] If called within a transaction
      #
      # @example
      #   user = User.new(id: 123)
      #   user.save_if_not_exists!  # => true or raises
      def save_if_not_exists!(update_expiration: true)
        # Prevent save_if_not_exists! within transaction - needs to read existence state
        if Fiber[:familia_transaction]
          raise Familia::OperationModeError, <<~ERROR_MESSAGE
            Cannot call save_if_not_exists! within a transaction. This method
            must be called outside transactions to properly check existence.
          ERROR_MESSAGE
        end

        identifier_field = self.class.identifier_field

        Familia.debug "[save_if_not_exists]: #{self.class} #{identifier_field}=#{identifier}"
        Familia.trace :SAVE_IF_NOT_EXISTS, nil, self.class.uri if Familia.debug?

        # Prepare object for persistence (timestamps, validation)
        prepare_for_save

        # Drive WATCH + MULTI/EXEC through a SINGLE resolved connection so the
        # optimistic lock is effective (the primitive owns abort detection and
        # retry). The existence check runs in the WATCH window: if the key is
        # created between WATCH and EXEC, Redis aborts and the primitive retries.
        result = Familia::Connection::TransactionCore.execute_watched_transaction(
          -> { dbclient }, watch_keys: [dbkey]
        ) do |conn|
          raise Familia::RecordExistsError, dbkey if exists?

          # Snapshot the instance-scoped index tracker in the WATCH window,
          # alongside the existence check and for the same reason: it is a
          # read, and reads inside the MULTI below return futures. Read here
          # rather than before the watched block so a WATCH abort re-reads it
          # on retry. Usually empty (this path only proceeds when the object
          # hash is absent), but a hash removed out of band -- delete!, or
          # expiry -- can leave entries behind. Those entries describe the
          # previous incarnation of this identifier, not the record being
          # created, so the transaction prunes them (#365): remove_from_* is
          # replayed with the recorded values and the tracker cleared. No
          # uniqueness guard is needed -- nothing is being joined.
          tracked_scopes = if respond_to?(:read_instance_index_scopes)
            read_instance_index_scopes
          else
            {}
          end

          Familia::Connection::TransactionCore.execute_normal_transaction(-> { conn }) do |_m|
            persist_to_storage(update_expiration, tracked_index_scopes: tracked_scopes,
                                                  prune_stale_tracker: true)
          end
        end

        Familia.debug "[save_if_not_exists]: result=#{result.inspect}"

        # Clear dirty tracking after successful save
        clear_dirty! if persisted_successfully?(result)

        # Return boolean indicating success (consistent with save method)
        persisted_successfully?(result)
      end

      # Non-raising variant of save_if_not_exists!
      #
      # @return [Boolean] true on success, false if object exists
      # @raise [Familia::OptimisticLockError] If concurrency conflict persists after retries
      def save_if_not_exists(...)
        save_if_not_exists!(...)
      rescue RecordExistsError
        false
      end

      # Commits object fields to the DB storage.
      #
      # Persists the current state of all object fields to the DB using HMSET.
      # Optionally updates the key's expiration time if the feature is enabled
      # for the object's class.
      #
      # Unlike +save+, this method does not touch the created/updated
      # timestamps. Class-level unique indexes are guarded and claimed before
      # the transaction opens (see #prepare_for_partial_write) and re-affirmed
      # inside it via #auto_update_class_indexes, so indexed lookups stay
      # consistent with the stored hash (#308). It also updates the
      # class-level +instances+ sorted set via +touch_instances!+, so the
      # object will appear in +instances.to_a+ listings. Use this for updating
      # fields on an object that is already persisted and tracked.
      #
      # @param update_expiration [Boolean] Whether to update the expiration time
      #   of the Valkey key. Defaults to true.
      #
      # @return [Object] The result of the HMSET operation from the DB.
      # @raise [Familia::RecordExistsError] if a class-level unique index
      #   already maps an indexed field's value to another record. Raised
      #   before the transaction opens; the object hash is untouched.
      #
      # @example Basic usage
      #   user.name = "John"
      #   user.email = "john@example.com"
      #   result = user.commit_fields
      #
      # @example Without updating expiration
      #   result = user.commit_fields(update_expiration: false)
      #
      # @note The expiration update is only performed for classes that have
      #   the expiration feature enabled. For others, it's a no-op.
      #
      # @note This method performs debug logging of the object's class, dbkey,
      #   and current state before committing to the DB.
      #
      # @see #save Full persistence lifecycle (timestamps, indexes, instances)
      #
      def commit_fields(update_expiration: true)
        prepared_value = to_h_for_storage
        Familia.debug "[commit_fields] Begin #{self.class} #{dbkey} #{prepared_value} (exp: #{update_expiration})"

        # Guard and claim class-level unique indexes before the MULTI opens
        # (fail-closed: a constraint violation leaves the hash untouched).
        prepare_for_partial_write

        result = transaction do |_conn|
          # Set all non-nil fields atomically
          hmset_result = hmset(prepared_value)

          # Remove any fields cleared to nil so their prior stored value is not
          # left stale (HMSET never deletes omitted fields).
          remove_stale_nil_fields

          # Maintain class-level indexes in the same transaction as the hash
          # write. Dirty tracking is still populated here (clear_dirty! runs
          # after EXEC), so changed indexed fields drop their stale entries.
          auto_update_class_indexes

          # Update expiration in same transaction to ensure atomicity
          self.update_expiration if hmset_result && update_expiration

          # Touch instances timeline so the object is visible to list-based
          # enumeration (instances.to_a, count, etc.). Skip it when nothing was
          # persisted and no hash key exists -- otherwise the identifier is
          # registered in `instances` pointing at a missing hash (see
          # {#persist_to_storage}).
          touch_instances! if hmset_result && !prepared_value.empty?

          hmset_result
        end

        # Clear dirty tracking after successful commit
        clear_dirty! if persisted_successfully?(result)

        result
      end

      # Whether a persistence MULTI/EXEC committed cleanly. A MultiResult is
      # successful when no queued command returned an Exception; a nil result
      # (e.g. a discarded/aborted transaction) is a failure. Shared by save,
      # save_if_not_exists!, commit_fields, and multi_field_update so they all
      # interpret the transaction result the same way -- a partial-command
      # failure must not clear dirty state or report success. Mirrors
      # AtomicWrite#atomic_write_success?.
      #
      # @param result [MultiResult, nil]
      # @return [Boolean]
      def persisted_successfully?(result)
        return false if result.nil?
        return result.successful? if result.is_a?(Familia::MultiResult)

        true
      end
      private :persisted_successfully?

      # Snapshot of in-memory state for the fields multi_field_update is about
      # to mutate: ivar value plus whether the field was already dirty. Only
      # fields with a plain setter are captured -- they are the only ones the
      # setter loop mutates.
      #
      # @param field_names [Array<Symbol, String>]
      # @return [Array<Array(Symbol, Object, Boolean)>]
      def capture_field_rollback_state(field_names)
        field_names.filter_map do |field|
          next unless respond_to?(:"#{field}=")

          [field.to_sym, instance_variable_get(:"@#{field}"), dirty?(field)]
        end
      end
      private :capture_field_rollback_state

      # Restores a {#capture_field_rollback_state} snapshot. Writes the ivar
      # directly (bypassing the setter) so the rollback itself records no new
      # dirty entries; a field that was clean before the failed write is
      # cleared, while one that was already dirty keeps its original baseline
      # (mark_dirty! never overwrites it).
      #
      # @param snapshot [Array<Array(Symbol, Object, Boolean)>]
      # @return [void]
      def restore_field_rollback_state(snapshot)
        snapshot.each do |field, old_value, was_dirty|
          instance_variable_set(:"@#{field}", old_value)
          clear_dirty!(field) unless was_dirty
        end
        nil
      end
      private :restore_field_rollback_state

      # Updates multiple fields atomically in a Database transaction.
      #
      # Values bypass the field setters on the write path, so field-type
      # semantics are enforced up front: transient fields are rejected (they
      # are never persisted), and encrypted fields only accept nil (deletes
      # the field) or the ConcealedString returned by the field getter --
      # raw plaintext never reaches the database. To encrypt a new plaintext
      # value, use the field setter followed by save or save_fields.
      #
      # Class-level indexes on the written fields are maintained (#308): the
      # in-memory setters are applied before the transaction so dirty tracking
      # captures the old values, unique indexes are guarded and claimed before
      # the MULTI opens (see #prepare_for_partial_write), and the index
      # entries are updated inside the same transaction as the hash write. On
      # a failed claim or transaction the in-memory state is rolled back to
      # its pre-call values, so a failed update never leaves the object
      # diverged from storage.
      #
      # @param kwargs [Hash] Field names and values to update. Special key :update_expiration
      #   controls whether to update key expiration (default: true)
      # @return [MultiResult] Transaction result
      # @raise [ArgumentError] if a field is undeclared, transient, or an
      #   encrypted field given a value that is not nil or a ConcealedString
      # @raise [Familia::RecordExistsError] if a class-level unique index
      #   already maps a written field's value to another record. Raised
      #   before the transaction opens; the object hash is untouched.
      #
      # @example Update multiple fields without affecting expiration
      #   metadata.multi_field_update(viewed: 1, updated: Familia.now.to_i, update_expiration: false)
      #
      # @example Update fields with expiration refresh
      #   user.multi_field_update(name: "John", email: "john@example.com")
      #
      def multi_field_update(**kwargs)
        update_expiration = kwargs.delete(:update_expiration) { true }
        fields = kwargs

        guard_persistable_fields!(fields)
        Familia.trace :MULTI_FIELD_UPDATE, nil, fields.keys if Familia.debug?

        # Apply the setters BEFORE the claim and the transaction, so dirty
        # tracking captures the old values (auto_update_class_indexes reads
        # them to drop stale index entries) and the generated claim/update
        # index methods -- which read the field getters -- see the values
        # being written. The snapshot below restores the pre-call in-memory
        # state (ivar value and dirty status) if anything fails, preserving
        # the documented never-diverged rollback semantics.
        rollback = capture_field_rollback_state(fields.keys)

        begin
          fields.each do |field, value|
            send(:"#{field}=", value) if respond_to?(:"#{field}=")
          end

          # Guard and claim class-level unique indexes before the MULTI opens
          # (fail-closed: a constraint violation leaves the hash untouched).
          prepare_for_partial_write(fields.keys)

          result = transaction do |_conn|
            # 1. Update all fields atomically. A nil value deletes the field
            # rather than storing "null", so absence stays authoritative (see
            # Serialization#to_h_for_storage).
            fields.each do |field, value|
              if value.nil?
                remove_field(field)
              else
                hset field, serialize_value(value)
              end
            end

            # 2. Maintain class-level indexes on the written fields in the
            # same transaction as the hash write.
            auto_update_class_indexes(only: fields.keys)

            # 3. Update expiration in same transaction
            self.update_expiration if update_expiration

            # 4. Register in instances sorted set so the object is visible
            # to list-based enumeration (instances.to_a, count, etc.)
            touch_instances!
          end
        rescue StandardError
          restore_field_rollback_state(rollback)
          raise
        end

        if result.is_a?(MultiResult) && result.successful?
          clear_dirty!(*fields.keys)
        else
          restore_field_rollback_state(rollback)
        end

        result
      end

      # Atomically writes multiple fields to the database using a single HMSET.
      #
      # This is the multi-field equivalent of the fast_writer (!) methods.
      # It sets all instance variables, serializes the values, and persists
      # them in one HMSET command within a transaction. More efficient than
      # multi_field_update (which does individual HSET per field) when writing
      # several fields at once.
      #
      # Values bypass the field setters on the write path, so field-type
      # semantics are enforced up front: transient fields are rejected (they
      # are never persisted), and encrypted fields only accept nil (deletes
      # the field) or the ConcealedString returned by the field getter --
      # raw plaintext never reaches the database. To encrypt a new plaintext
      # value, use the field setter followed by save or save_fields.
      #
      # Fields backing a class-level index (unique_index or multi_index) are
      # refused outright: the one-HMSET contract leaves no room for the
      # out-of-transaction claim that index maintenance requires (ADR-0002),
      # and writing the hash without the index would leave lookups stale
      # (#308). Use multi_field_update or save for indexed fields. The check
      # is local metadata only -- no extra database round trips.
      #
      # @param kwargs [Hash] Field names and values to write. Special key
      #   :update_expiration controls whether to refresh key expiration
      #   (default: true).
      # @return [self] Returns self for method chaining
      # @raise [ArgumentError] if a field is undeclared, transient, or an
      #   encrypted field given a value that is not nil or a ConcealedString
      # @raise [Familia::IndexedFieldFastWriteError] if a field backs a
      #   class-level index. Raised before any write; the hash is untouched.
      #
      # @example Persist multiple fields atomically
      #   user.multi_field_fast_write(name: "Jane", email: "jane@example.com")
      #
      # @example Without updating expiration
      #   user.multi_field_fast_write(status: "active", update_expiration: false)
      #
      # @see #multi_field_update Similar but uses individual HSET per field
      # @see #save_fields Persists current in-memory values of named fields
      #
      def multi_field_fast_write(**kwargs)
        update_exp = kwargs.delete(:update_expiration) { true }
        fields = kwargs

        raise ArgumentError, 'No fields specified' if fields.empty?

        guard_persistable_fields!(fields)
        guard_unindexed_fields!(fields.keys)

        Familia.trace :MULTI_FIELD_FAST_WRITE, nil, fields.keys if Familia.debug?

        # Serialize values before the transaction (read-only on instance).
        # A nil value deletes the field rather than storing "null" (see
        # Serialization#to_h_for_storage), so split writes from removals.
        serialized = {}
        nil_fields = []
        fields.each do |field, value|
          if value.nil?
            nil_fields << field.to_s
          else
            serialized[field] = serialize_value(value)
          end
        end

        result = transaction do |_conn|
          hmset(serialized)

          dbclient.hdel(dbkey, *nil_fields) unless nil_fields.empty?

          update_expiration if update_exp

          touch_instances!
        end

        # Update in-memory state only after transaction succeeds,
        # so a failed transaction never leaves the object diverged.
        if result.is_a?(MultiResult) && result.successful?
          fields.each do |field, value|
            send(:"#{field}=", value) if respond_to?(:"#{field}=")
          end
          clear_dirty!(*fields.keys)
        end

        self
      end

      # Persists only the specified fields to Redis.
      #
      # Saves the current in-memory values of specified fields to Redis without
      # modifying them first. Fields must already be set on the instance.
      #
      # Class-level indexes on the written fields are maintained (#308):
      # unique indexes are guarded and claimed before the transaction opens
      # (see #prepare_for_partial_write), and the index entries are updated
      # inside the same transaction as the hash write. Indexes on fields not
      # named here are left untouched.
      #
      # @param field_names [Array<Symbol, String>] Names of fields to persist
      # @param update_expiration [Boolean] Whether to refresh key expiration
      # @return [self] Returns self for method chaining
      # @raise [Familia::RecordExistsError] if a class-level unique index
      #   already maps a written field's value to another record. Raised
      #   before the transaction opens; the object hash is untouched.
      #
      # @example Persist only passphrase fields after updating them
      #   customer.update_passphrase('secret').save_fields(:passphrase, :passphrase_encryption)
      #
      def save_fields(*field_names, update_expiration: true)
        raise ArgumentError, 'No fields specified' if field_names.empty?

        Familia.trace :SAVE_FIELDS, nil, field_names if Familia.debug?

        # Build hash of non-nil field values; collect nil'd fields for removal.
        # A nil field is deleted rather than stored as "null" so that absence
        # stays authoritative (see Serialization#to_h_for_storage). Built
        # before the transaction so an unknown field fails before any claim
        # or write happens.
        fields_hash = {}
        nil_fields = []
        field_names.each do |field|
          field_sym = field.to_sym
          raise ArgumentError, "Unknown field: #{field}" unless respond_to?(field_sym)

          value = send(field_sym)
          if value.nil?
            nil_fields << field.to_s
          else
            fields_hash[field] = serialize_value(value)
          end
        end

        # Guard and claim class-level unique indexes before the MULTI opens
        # (fail-closed: a constraint violation leaves the hash untouched).
        prepare_for_partial_write(field_names)

        result = transaction do |_conn|
          # Set all non-nil fields at once (hmset no-ops on an empty hash)
          hmset(fields_hash)

          # Remove any nil'd fields so their prior stored value does not linger
          dbclient.hdel(dbkey, *nil_fields) unless nil_fields.empty?

          # Maintain class-level indexes on the written fields in the same
          # transaction as the hash write
          auto_update_class_indexes(only: field_names)

          # Update expiration in same transaction
          self.update_expiration if update_expiration

          # Touch instances timeline so the object is visible
          # to list-based enumeration (instances.to_a, count, etc.)
          touch_instances!
        end

        clear_dirty!(*field_names) if persisted_successfully?(result)

        self
      end

      # Updates the object by applying multiple field values.
      #
      # Sets multiple attributes on the object instance using their corresponding
      # setter methods. Only fields that have defined setter methods will be updated.
      #
      # @param fields [Hash] Hash of field names (as keys) and their values to apply
      #   to the object instance.
      #
      # @return [self] Returns the updated object instance for method chaining.
      #
      # @example Update multiple fields on an object
      #   user.apply_fields(name: "John", email: "john@example.com", age: 30)
      #   # => #<User:0x007f8a1c8b0a28 @name="John", @email="john@example.com", @age=30>
      #
      def apply_fields(**fields)
        guard_allowed_fields!(fields.keys)
        fields.each do |field, value|
          send("#{field}=", value) if respond_to?("#{field}=")
        end
        self
      end

      # Permanently removes this object and its related fields from the DB.
      #
      # Deletes the object's database key, all related fields (lists, sets,
      # hashes, etc.), and removes the identifier from the class-level
      # +instances+ sorted set. This operation is irreversible.
      #
      # This is the instance-level counterpart to the class method of the
      # same name. Both clean up related fields and the main hash key, but
      # only this instance method removes from +instances+. See the class
      # method's documentation for that known gap.
      #
      # @return [void]
      #
      # @example Remove a user object from storage
      #   user = User.new(id: 123)
      #   user.destroy!
      #   # Object is now permanently removed from the DB
      #
      # @note This method provides high-level object lifecycle management.
      #   It operates at the object level for ORM-style operations, while
      #   `delete!` operates directly on database keys. Use `destroy!` when
      #   removing complete objects from the system.
      #
      # @note When debugging is enabled, this method will trace the deletion
      #   operation for diagnostic purposes.
      #
      # @see #delete! The underlying method that performs the key deletion
      #
      def destroy!
        Familia.trace :DESTROY!, dbkey, self.class.uri if Familia.debug?

        # Pre-read instance-scoped index tracker before MULTI/EXEC
        # (HGETALL returns futures inside a transaction, not values).
        # Maps "<scope_config>\t<index_name>\t<scope_id>" => indexed value.
        tracked_scopes = if respond_to?(:read_instance_index_scopes)
          read_instance_index_scopes
        else
          {}
        end

        result = transaction do |_conn|
          delete!

          if self.class.relations?
            if Familia.debug?
              Familia.trace :DELETE_RELATED_FIELDS!, nil,
                            "#{self.class} has relations: #{self.class.related_fields.keys}"
            end

            self.class.related_fields.each_key do |name|
              obj = send(name)
              if Familia.debug?
                Familia.trace :DELETE_RELATED_FIELD, name, "Deleting related field #{name} (#{obj.dbkey})"
              end
              obj.delete!
            end
          end

          # Clean up instance-scoped index entries (#282) using
          # pre-read tracker data. Must precede class-level cleanup.
          if !tracked_scopes.empty? && respond_to?(:remove_tracked_index_entries!)
            remove_tracked_index_entries!(tracked_scopes)
          end

          # Clean up class-level index entries (#241)
          remove_from_class_indexes!

          remove_from_instances!
        end

        # Structured lifecycle logging and instrumentation
        Familia.debug 'Horreum destroyed',
          class: self.class.name,
          identifier: identifier,
          key: dbkey

        Familia::Instrumentation.notify_lifecycle(:destroy, self, key: dbkey)

        result
      end

      # Clears all fields by setting them to nil.
      #
      # Resets all object fields to nil values, effectively clearing the object's
      # state. This operation affects all fields defined on the object's class,
      # setting each one to nil through their corresponding setter methods.
      #
      # @return [void]
      #
      # @example Clear all fields on an object
      #   user.name = "John"
      #   user.email = "john@example.com"
      #   user.clear_fields!
      #   # => user.name and user.email are now nil
      #
      # @note This operation does not persist the changes to the DB. Call save
      #   after clear_fields! if you want to persist the cleared state.
      #
      def clear_fields!
        Familia.trace :CLEAR_FIELDS!, dbkey, self.class.uri
        self.class.field_method_map.each_value { |method_name| send("#{method_name}=", nil) }
      end

      # Refreshes the object state from the DB storage.
      #
      # Reloads all persistent field values from the DB, overwriting any unsaved
      # changes in the current object instance. This operation synchronizes the
      # object with its stored state in the database.
      #
      # @return [void]
      #
      # @raise [Familia::KeyNotFoundError] If the Valkey key does not exist
      #
      # @example Refresh object from the DB
      #   user.name = "Changed Name"  # unsaved change
      #   user.refresh!
      #   # => user.name is now the value from the DB storage
      #
      # @note This method discards any unsaved changes to the object. Use with
      #   caution when the object has been modified but not yet persisted.
      #
      # @note Transient fields are reset to nil during refresh since they have
      #   no authoritative source in Valkey storage.
      #
      def refresh!
        Familia.trace :REFRESH, nil, self.class.uri if Familia.debug?
        raise Familia::KeyNotFoundError, dbkey unless dbclient.exists(dbkey)

        fields = hgetall
        Familia.debug "[refresh!] #{self.class} #{dbkey} fields:#{fields.keys}"

        # Reset transient fields to nil for semantic clarity and ORM consistency
        # Transient fields have no authoritative source, so they should return to
        # their uninitialized state during refresh operations
        reset_transient_fields!

        result = naive_refresh(**fields)

        # Clear dirty tracking since object now matches DB state
        clear_dirty!

        result
      end

      # Refreshes object state from the DB and returns self for method chaining.
      #
      # Loads the current state of the object from the DB storage, updating all
      # field values to match their persisted state. This method provides a
      # chainable interface to the refresh! operation.
      #
      # @return [self] The refreshed object instance, enabling method chaining
      #
      # @raise [Familia::KeyNotFoundError] If the Valkey key does not exist
      #
      # @example Refresh and chain operations
      #   user.refresh.save
      #   user.refresh.apply_fields(status: 'active')
      #
      # @see #refresh! The underlying refresh operation
      #
      def refresh
        refresh!
        self
      end

      # Updates this object's timestamp in the class-level instances sorted set.
      #
      # The instances sorted set is a timeline of last-modified times, not
      # a registry. This method performs a ZADD with the current timestamp as
      # score: if the identifier is already present the score is updated;
      # if absent, it is added. No preliminary member? check is performed,
      # making this safe to call inside MULTI/EXEC transactions where read
      # operations return uninspectable Future objects.
      #
      # @return [Object] The return value of the ZADD command (boolean or
      #   Redis::Future inside a transaction)
      #
      # @raise [Familia::NoIdentifier] if the identifier is nil or empty
      #
      # @example Touch after commit_fields
      #   user.commit_fields
      #   user.touch_instances!  # now visible in User.instances
      #
      # @example Safe to call multiple times (updates timestamp)
      #   user.touch_instances!
      #   user.touch_instances!  # score updated, no duplicate
      #
      def touch_instances!
        ident = identifier
        raise Familia::NoIdentifier, "No identifier for #{self.class}" if ident.nil? || ident.to_s.empty?

        self.class.instances.add(self, Familia.now)
      end

      # Removes this object from the class-level instances sorted set.
      #
      # Symmetric counterpart to {#touch_instances!}. After calling this
      # method the object will no longer appear in +instances.to_a+ listings
      # or be counted by +instances.count+. The underlying database hash key
      # is NOT deleted -- use {#destroy!} for full removal.
      #
      # Safe to call inside MULTI/EXEC transactions (no read-before-write).
      #
      # @return [Object] The return value of the ZREM command (integer or
      #   Redis::Future inside a transaction)
      #
      # @raise [Familia::NoIdentifier] if the identifier is nil or empty
      #
      # @example Remove from instances without deleting data
      #   user.remove_from_instances!  # no longer in User.instances
      #   user.exists?                 # => true (hash key still present)
      #
      # @see #touch_instances! The symmetric add operation
      # @see #destroy! Full object removal (data + instances)
      #
      def remove_from_instances!
        ident = identifier
        raise Familia::NoIdentifier, "No identifier for #{self.class}" if ident.nil? || ident.to_s.empty?

        self.class.instances.remove(ident)
      end

      # Convenience methods that forward to the class method of the same name
      def transaction(...) = self.class.transaction(...)
      def pipelined(...) = self.class.pipelined(...)
      def dbclient(...) = self.class.dbclient(...)

      private

      # Validates that all field names are declared Familia fields.
      #
      # Prevents mass-assignment of arbitrary setter methods (e.g. role=,
      # admin=) that are not declared fields. This is a defense-in-depth
      # measure for downstream callers that may inadvertently pass
      # unsanitized input to batch methods.
      #
      # The allowed set is every field registered on the class
      # (field_method_map), whichever DSL declared it -- `field`,
      # `encrypted_field`, `transient_field`, or a feature that registers its
      # own (objid, extid). This guard answers "is this a field?" and nothing
      # more; whether a declared field may actually be persisted by a batch
      # write is guard_persistable_fields!'s decision, and only the batch-write
      # methods call it -- apply_fields runs this guard alone, so a transient
      # field passed there reaches its setter and stays in memory.
      #
      # @param names [Array<Symbol, String>] field names to validate
      # @raise [ArgumentError] if any name is not a declared field
      # @return [void]
      #
      def guard_allowed_fields!(names)
        allowed = self.class.field_method_map.keys
        unknown = names.map(&:to_sym) - allowed
        return if unknown.empty?

        raise ArgumentError,
          "Undeclared fields for #{self.class}: #{unknown.join(', ')}. " \
          'Mass assignment is limited to fields declared on the class.'
      end

      # Validates that a batch of field/value pairs may be written to storage.
      #
      # The batch-write methods (multi_field_update, multi_field_fast_write)
      # persist caller-supplied values directly via serialize_value, bypassing
      # the field setters that normally enforce field-type semantics. This
      # guard restores those semantics up front:
      #
      # - Transient fields are never persisted, so passing one is an error.
      # - Encrypted fields must never receive raw plaintext: serialize_value
      #   would store it verbatim. Only nil (field deletion) or an actual
      #   ConcealedString -- the type returned by the encrypted field getter --
      #   is accepted. This checks the type, not its provenance: a
      #   ConcealedString belonging to another record or field is accepted
      #   here and will fail its AAD check on decrypt. The setter path
      #   (belongs_to_context?) is what validates provenance.
      #
      # The ConcealedString check is a type check, not a duck type check. Any
      # object exposing #encrypted_value would satisfy serialize_value and be
      # persisted verbatim, so accepting the interface rather than the type
      # would let a caller-supplied object put plaintext in the database
      # through the very guard meant to prevent it. serialize_value itself
      # stays duck-typed: it is the general serializer for every write path,
      # and narrowing it is a broader change than this guard warrants.
      #
      # @param fields [Hash{Symbol => Object}] field names mapped to the
      #   values about to be persisted
      # @raise [ArgumentError] if any field is undeclared, transient, or an
      #   encrypted field given a value that is neither nil nor a
      #   ConcealedString
      # @return [void]
      #
      def guard_persistable_fields!(fields)
        guard_allowed_fields!(fields.keys)

        field_types = self.class.field_types
        fields.each do |name, value|
          field_type = field_types[name.to_sym]

          if field_type.transient?
            raise ArgumentError,
              "Transient field #{name} for #{self.class} is never persisted " \
              'and cannot be written with batch persistence methods.'
          end

          next unless field_type.category == :encrypted
          next if value.nil? || value.is_a?(::ConcealedString)

          raise ArgumentError,
            "Encrypted field #{name} for #{self.class} cannot be written from " \
            "a #{value.class} here. Pass the ConcealedString from the field " \
            'getter, or use the field setter followed by save/save_fields.'
        end
      end

      # Refuses fields that back a class-level index. The fast-write path is
      # a single HMSET with no out-of-transaction claim, so it cannot maintain
      # index consistency without violating the fail-closed ordering in
      # ADR-0002 (#308). Purely a local metadata check -- no database reads.
      #
      # @param field_names [Array<Symbol, String>] fields about to be written
      # @raise [Familia::IndexedFieldFastWriteError] if any field backs a
      #   class-level index
      # @return [void]
      #
      def guard_unindexed_fields!(field_names)
        return unless self.class.respond_to?(:indexing_relationships)

        field_names.each do |field|
          rel = self.class.indexing_relationships.find do |candidate|
            candidate.class_level? && candidate.field == field.to_sym
          end
          next unless rel

          raise Familia::IndexedFieldFastWriteError.new(field, rel.index_name)
        end
      end
      private :guard_unindexed_fields!

      # Reset all transient fields to nil
      #
      # This method ensures that transient fields return to their uninitialized
      # state during refresh operations. This provides semantic clarity (refresh
      # means "reload from authoritative source"), ORM consistency with other
      # frameworks, and prevents stale transient data accumulation.
      #
      # @return [void]
      #
      def reset_transient_fields!
        return unless self.class.respond_to?(:transient_fields)

        self.class.transient_fields.each do |field_name|
          field_type = self.class.field_types[field_name]
          next unless field_type&.method_name

          # UnsortedSet the transient field back to nil
          send("#{field_type.method_name}=", nil)
          Familia.debug "[reset_transient_fields!] Reset #{field_name} to nil"
        end
      end

      # Whether +field_value+ was claimed for +index_name+ during the current
      # {#prepare_for_save}.
      #
      # The generated +add_to_class_*+ mutators consult this before issuing the
      # in-MULTI HSET: that write is only sound as a re-affirmation of a claim
      # already taken server-side, so a caller who opened their own transaction
      # without claiming gets an error instead of the old blind write.
      #
      # The ledger records the *value* claimed, not just the index name. An
      # index-name-only ledger would vouch for a value that was never claimed
      # in two reachable cases:
      #
      #   1. +atomic_write+ runs {#prepare_for_save} (which claims the value the
      #      record holds at that moment) and then yields the caller's block
      #      INSIDE the MULTI. A block that reassigns the indexed field would
      #      reach the in-MULTI HSET with a value no CAS ever saw.
      #   2. The ledger outlives the save that populated it. A later
      #      caller-opened transaction touching the same instance after the
      #      indexed field changed would find the index still marked claimed.
      #
      # Both are the blind write this PR removes, so the comparison is against
      # the value. +field_value+ is compared as a string because that is the
      # form both {Familia::HashKey#claim_field} and the HSET use.
      #
      # @param index_name [Symbol]
      # @param field_value [Object] the value about to be written
      # @return [Boolean]
      def unique_index_claimed?(index_name, field_value)
        return false if field_value.nil?

        claim = unique_index_claims[index_name]
        return false unless claim

        # Both halves matter. The value half is the point of the ledger. The
        # identifier half keeps a copied instance from spending the original's
        # claim: #dup shallow-copies ivars, so a dup shares this very Hash, and
        # a Marshal round-trip carries it along too. A copy that kept the same
        # identifier is the same owner and may re-affirm; one that was given a
        # new identifier owns nothing.
        claim[0] == identifier.to_s && claim[1] == field_value.to_s
      end

      # The claim ledger: { index_name => [identifier, claimed value] }.
      #
      # @return [Hash{Symbol => Array(String, String)}]
      def unique_index_claims
        @unique_index_claims ||= {}
      end
      private :unique_index_claims

      # Records that +field_value+ is now claimed for +index_name+.
      #
      # Called by the generated +claim_unique_<index>!+ methods, so that taking
      # a claim directly -- the documented way to make an in-transaction write
      # legal -- is enough on its own. {#claim_unique_indexes!} resets the
      # ledger and then relies on the same recording.
      #
      # The value is snapshotted, not referenced: +String#to_s+ returns +self+,
      # so storing it raw would let an in-place mutation of the record's own
      # field (+email.downcase!+, +email << suffix+) rewrite the ledger entry in
      # lockstep and smuggle a value the CAS never saw past the check.
      #
      # @param index_name [Symbol]
      # @param field_value [Object]
      # @return [void]
      def record_unique_index_claim(index_name, field_value)
        unique_index_claims[index_name] = [-identifier.to_s, -field_value.to_s]
        nil
      end
      private :record_unique_index_claim

      # Drops the ledger entry for +index_name+ when it records +field_value+.
      #
      # A ledger entry asserts "this record holds a server-side claim on this
      # value". Releasing the claim without dropping the entry leaves the
      # assertion false, and a later in-transaction write would re-affirm a
      # claim that no longer exists -- reinstating the blind write over whoever
      # legitimately took the value in the meantime.
      #
      # Value-matched, because +update_in_class_*+ releases the OLD value while
      # the ledger legitimately holds a claim on the NEW one.
      #
      # @param index_name [Symbol]
      # @param field_value [Object] the value being released
      # @return [void]
      def forget_unique_index_claim(index_name, field_value)
        return if field_value.nil?

        claim = unique_index_claims[index_name]
        unique_index_claims.delete(index_name) if claim && claim[1] == field_value.to_s
        nil
      end
      private :forget_unique_index_claim

      # Atomically claims this record's value in every class-level unique index.
      #
      # Runs OUTSIDE the save transaction (from {#prepare_for_save}), because a
      # CAS queued inside a MULTI cannot abort the other queued commands and its
      # verdict comes back as a Future. Once claimed, the index HSET that
      # +persist_to_storage+ issues inside the MULTI is an idempotent
      # re-affirmation of a value this record already owns.
      #
      # Claims are taken in relationship order. If a later index collides, the
      # entries this call *created* are released before the error propagates --
      # otherwise a two-unique-index class could permanently strand a value in
      # the first index for a record that never got saved. Entries that were
      # already owned by this record (+:owned+) are left alone; they predate the
      # call and rolling them back would destroy valid state.
      #
      # @param only [Array<Symbol, String>, nil] restrict claiming to indexes
      #   on these fields; nil claims every class-level unique index. Partial
      #   writers pass the fields they are about to write, so indexes outside
      #   the write are neither claimed nor (later) re-affirmed.
      # @raise [Familia::RecordExistsError] if another record owns a value
      # @return [void]
      #
      # @see Familia::HashKey#claim_field The server-side CAS.
      # @see docs/adr/0002-watch-for-private-keys-lua-for-shared-keys.md
      #
      def claim_unique_indexes!(only: nil)
        fields = only&.map(&:to_sym)

        # Reset the ledger before anything can bail out: a claim recorded by a
        # previous save must never vouch for this one. Private, but reachable
        # via send, so it cannot assume prepare_for_save is the only caller.
        # A filtered call drops only the entries for the indexes it is about
        # to re-take (below): indexes outside the written fields are not
        # re-affirmed by a partial write, so their claims are neither spent
        # nor endangered by it.
        @unique_index_claims = {} if fields.nil?

        return unless self.class.respond_to?(:indexing_relationships)

        created = []

        begin
          class_level_unique_indexes_for(fields).each do |rel|
            # Drop the stale ledger entry before re-taking the claim. On an
            # unfiltered run the ledger was just reset, so this is a no-op.
            unique_index_claims.delete(rel.index_name)

            created << rel.index_name if claim_single_unique_index(rel) == :created
          end
        rescue StandardError
          release_created_index_claims!(created)
          raise
        end

        nil
      end

      # The class-level unique indexing relationships whose indexed field is
      # in +fields+ (nil means no filter -- all of them).
      #
      # @param fields [Array<Symbol>, nil]
      # @return [Array<IndexingRelationship>]
      def class_level_unique_indexes_for(fields)
        rels = []
        each_class_level_unique_index do |rel|
          rels << rel if fields.nil? || fields.include?(rel.field)
        end
        rels
      end
      private :class_level_unique_indexes_for

      # Takes the server-side claim for a single unique index relationship.
      #
      # The ledger entry is written by claim_unique_<index>! itself. A nil
      # outcome means the record has no value for the indexed field --
      # nothing was claimed, so nothing was recorded and nothing may be
      # re-affirmed later.
      #
      # @param rel [IndexingRelationship] a class-level unique relationship
      # @return [Symbol, nil] :created, :owned, or nil when nothing claimed
      def claim_single_unique_index(rel)
        claim_method = :"claim_unique_#{rel.index_name}!"
        return nil unless respond_to?(claim_method)

        outcome = send(claim_method)
        outcome.is_a?(Symbol) ? outcome : nil
      end
      private :claim_single_unique_index

      # Releases index entries created earlier in a {#claim_unique_indexes!}
      # run that then failed. Best-effort: a release that itself fails must not
      # mask the original constraint violation.
      #
      # @param index_names [Array<Symbol>]
      # @return [void]
      def release_created_index_claims!(index_names)
        index_names.each do |index_name|
          release_method = :"release_unique_#{index_name}!"
          next unless respond_to?(release_method)

          begin
            send(release_method)
          rescue StandardError => e
            Familia.warn <<~LOG_MESSAGE
              [claim_unique_indexes!] Failed to release #{self.class}##{index_name} claim after a later conflict: #{e.message}. A stale entry may remain until the next save.
            LOG_MESSAGE
          end
        end
      end
      private :release_created_index_claims!

      # Yields each class-level unique indexing relationship.
      #
      # @yield [IndexingRelationship]
      # @return [void]
      def each_class_level_unique_index
        self.class.indexing_relationships.each do |rel|
          next unless rel.cardinality == :unique
          next unless rel.class_level?

          yield rel
        end
      end
      private :each_class_level_unique_index

      # Validates that unique index constraints are satisfied before saving
      # This must be called OUTSIDE of transactions to allow reading current values
      #
      # @raise [Familia::RecordExistsError] If a unique index constraint is violated
      #   for any class-level unique_index relationships
      #
      # @note Only validates class-level unique indexes (without within: parameter).
      #   Instance-scoped indexes (with within:) are validated automatically when
      #   calling add_to_*_index methods:
      #
      # @example Instance-scoped indexes need to be called explicitly but when
      # called they will perform the validation automatically:
      #   employee.add_to_company_badge_index(company) # raises on duplicate
      #
      # @return [void]
      #
      # @note This is a fast-fail read, not the enforcement. Two savers can both
      #   pass it for the same value; {#claim_unique_indexes!} is what actually
      #   settles the race. It still earns its keep by checking EVERY unique
      #   index before any claim is written, so a collision on the second index
      #   of a two-index class fails before the first index is touched.
      #
      # @param only [Array<Symbol, String>, nil] restrict the check to indexes
      #   on these fields; nil checks every class-level unique index
      #
      def guard_unique_indexes!(only: nil)
        return unless self.class.respond_to?(:indexing_relationships)

        fields = only&.map(&:to_sym)

        each_class_level_unique_index do |rel|
          next if fields && !fields.include?(rel.field)

          # Call the validation method if it exists
          validate_method = :"guard_unique_#{rel.index_name}!"
          send(validate_method) if respond_to?(validate_method)
        end

        nil # Explicit nil return as documented
      end

      # Automatically maintains class-level indexes after save.
      #
      # Iterates the class-level indexing relationships and applies the
      # appropriate index mutation for each (see #apply_class_index_change).
      # Only class-level indexes are processed here; instance-scoped indexes
      # (declared with within: a class) require a scope instance and must be
      # populated explicitly.
      #
      # The previous value of each changed field is read from dirty tracking,
      # which is still populated at this point (clear_dirty! runs AFTER the save
      # transaction), so a changed indexed field can have its stale entry removed
      # in the same transaction:
      #
      # - unique_index: routes through update_in_class_* (old-value-aware
      #   HDEL + HSET) so changing an indexed field removes the prior mapping
      #   atomically and the freed value can be reused.
      # - multi_index: routes through add_to_class_* (add-only); prior buckets
      #   are intentionally retained on a value change (see the
      #   class_level_multi_index tests).
      #
      # @return [void]
      #
      # @example Automatic indexing on save
      #   class Customer < Familia::Horreum
      #     feature :relationships
      #     unique_index :email, :email_lookup
      #   end
      #
      #   customer = Customer.new(email: 'test@example.com')
      #   customer.save  # Automatically calls update_in_class_email_lookup
      #
      # @note Only class-level unique_index declarations auto-populate here.
      #   Instance-scoped indexes (with within:) need a scope instance, which
      #   save cannot invent, so their initial add_to_* stays manual. Once
      #   tracked, they are refreshed alongside this method by
      #   #auto_update_instance_indexes and removed by destroy! (#282).
      #
      # @see #apply_class_index_change For the per-relationship routing.
      # @see Familia::Features::Relationships::Indexing For index declaration details
      #
      # @param only [Array<Symbol, String>, nil] restrict maintenance to
      #   indexes on these fields; nil processes every class-level index. The
      #   partial writers pass the fields they wrote, matching the claims
      #   taken by their #prepare_for_partial_write call -- an unfiltered run
      #   would re-affirm indexes no claim was recorded for and raise
      #   Familia::OperationModeError inside the MULTI.
      #
      def auto_update_class_indexes(only: nil)
        return unless self.class.respond_to?(:indexing_relationships)

        fields = only&.map(&:to_sym)

        # Dirty tracking is still populated here: clear_dirty! runs AFTER the save
        # transaction, while this method runs INSIDE it (via persist_to_storage
        # and the partial writers, #308). Both `new` and the load path clear
        # dirty after construction, so a captured old value is the
        # previously-persisted value -- exactly what we must remove from the
        # index when an indexed field changed.
        changes = changed_fields # { field => [old_value, new_value] }

        self.class.indexing_relationships.each do |rel|
          unless rel.class_level?
            Familia.debug <<~LOG_MESSAGE
              [auto_update_class_indexes] Skipping #{rel.index_name} (requires scope context)
            LOG_MESSAGE
            next
          end

          next if fields && !fields.include?(rel.field)

          apply_class_index_change(rel, changes)
        end
      end

      # Maintains a single class-level index entry for +rel+ during save.
      #
      # @param rel [IndexingRelationship] a class-level indexing relationship
      # @param changes [Hash] dirty-tracking diff { field => [old_value, new_value] }
      # @return [void]
      def apply_class_index_change(rel, changes)
        update_method = :"update_in_class_#{rel.index_name}"
        add_method = :"add_to_class_#{rel.index_name}"

        if rel.cardinality == :unique && respond_to?(update_method)
          # unique_index: use the old-value-aware update so a changed indexed
          # field removes its stale entry. Otherwise find_by_<field>(old_value)
          # resolves a tombstone and the freed value cannot be reused (the unique
          # guard sees the orphan). update_in_class_* always re-adds the current
          # value, so new records are still indexed; its reentrant transaction
          # joins this save's MULTI, so remove+add commit atomically.
          change = changes[rel.field]
          send(update_method, change && change.first)
        elsif respond_to?(add_method)
          # multi_index (and any add-only index): a value change does not retract
          # prior buckets -- by design (see class_level_multi_index tests).
          # HSET/SADD are idempotent so repeated saves stay safe.
          send(add_method)
        end
      end
      private :apply_class_index_change

      # Remove class-level index entries during destroy!
      #
      # Iterates through class-level indexing relationships and calls their
      # corresponding remove_from_class_* methods to purge stale entries.
      # Only processes class-level indexes (where within is nil or :class).
      # Instance-scoped indexes are handled separately via the reverse
      # index tracker (#282) — see remove_tracked_index_entries!.
      #
      # Called from inside destroy!'s MULTI/EXEC transaction so index
      # hash/set mutations are atomic with the object hash delete.
      #
      # @return [void]
      #
      def remove_from_class_indexes!
        return unless self.class.respond_to?(:indexing_relationships)

        self.class.indexing_relationships.each do |rel|
          next unless rel.class_level?

          remove_method = :"remove_from_class_#{rel.index_name}"
          if respond_to?(remove_method)
            send(remove_method)
          else
            Familia.debug <<~LOG_MESSAGE
              [remove_from_class_indexes!] Missing #{remove_method} for #{self.class}##{rel.index_name}; stale index entries may remain
            LOG_MESSAGE
          end
        end
      end

      # Prepares the object for persistence by setting timestamps and validating constraints
      #
      # This method is called by both save and save_if_not_exists to ensure consistent
      # preparation logic. It updates created/updated timestamps and validates unique
      # indexes before the transaction begins.
      #
      # @return [void]
      #
      def prepare_for_save
        # Update timestamp fields before saving
        self.created ||= Familia.now if respond_to?(:created)
        self.updated = Familia.now if respond_to?(:updated)

        # Read-only pre-check across all unique indexes; cheap, and fails
        # before any claim is written when a value is plainly taken.
        guard_unique_indexes!

        # Take the claims server-side. This is the enforcement, and it must
        # happen here -- outside the transaction the caller is about to open.
        # It also resets the claim ledger the in-MULTI writes consult, recording
        # which *value* each index was claimed for (see #unique_index_claimed?).
        claim_unique_indexes!
      end
      private :prepare_for_save

      # The prepare_for_save of the partial writers (commit_fields,
      # save_fields, multi_field_update): read-only guard plus server-side CAS
      # claim for class-level unique indexes, scoped to the fields being
      # written. Deliberately omits the timestamp mutation prepare_for_save
      # performs -- a partial write must not change created/updated (#308).
      #
      # Must run OUTSIDE the transaction the caller is about to open (see
      # #claim_unique_indexes!), which is what makes the write fail-closed: a
      # constraint violation raises before any hash command is queued. Inside
      # a caller's MULTI/pipeline the guard's index reads come back as futures
      # (truthy, never equal to the identifier), which would surface as a
      # spurious RecordExistsError -- so when a class-level unique index
      # covers the written fields, the write is refused outright with the
      # same OperationModeError save raises. Classes without a covering
      # unique index are untouched: no index work would happen, so their
      # in-transaction behavior is unchanged.
      #
      # @param field_names [Array<Symbol, String>, nil] fields about to be
      #   written; nil means the full hash is being written (commit_fields)
      # @raise [Familia::OperationModeError] if called within a transaction or
      #   pipeline while a class-level unique index covers the written fields
      # @raise [Familia::RecordExistsError] if another record owns a value
      # @return [void]
      #
      def prepare_for_partial_write(field_names = nil)
        if (Fiber[:familia_transaction] || Fiber[:familia_pipeline]) &&
           self.class.respond_to?(:indexing_relationships) &&
           !class_level_unique_indexes_for(field_names&.map(&:to_sym)).empty?
          raise Familia::OperationModeError, <<~ERROR_MESSAGE
            Cannot perform a partial write (commit_fields, save_fields, multi_field_update) on unique-indexed fields within a transaction or pipeline. Unique constraints require read operations whose results are unavailable inside MULTI, so perform the write outside the transaction.
          ERROR_MESSAGE
        end

        guard_unique_indexes!(only: field_names)
        claim_unique_indexes!(only: field_names)
      end
      private :prepare_for_partial_write

      # Names (as strings) of declared persistent fields whose current in-memory
      # value is nil. These are omitted from {Serialization#to_h_for_storage}, so
      # on an update their previously-stored value must be explicitly deleted.
      #
      # @return [Array<String>]
      #
      def nil_persistent_field_names
        self.class.persistent_fields.each_with_object([]) do |field, names|
          field_type = self.class.field_types[field]
          names << field.to_s if send(field_type.method_name).nil?
        end
      end
      private :nil_persistent_field_names

      # Deletes any now-nil persistent fields from the object hash so a value
      # cleared to nil does not leave a stale entry behind. This is what keeps
      # "absent" and "nil" the same observable state after a round trip, and
      # what makes HSETNX/HEXISTS on a nil'd field behave correctly.
      #
      # Because it removes every field that is nil in memory, save/commit_fields
      # are a full-overwrite of scalar state (see {#save}). A field managed out of
      # band (e.g. an HSETNX claim) that is still nil on this in-memory copy is
      # cleared by a full save; use the targeted writers or {#refresh!} to avoid
      # that.
      #
      # Intended to run inside the save/commit transaction. HDEL of an absent
      # field is a harmless no-op, so it is safe on both the create and update
      # paths (and queues cleanly inside MULTI/EXEC).
      #
      # @return [void]
      #
      def remove_stale_nil_fields
        names = nil_persistent_field_names
        return if names.empty?

        Familia.trace :HDEL, nil, names if Familia.debug?
        dbclient.hdel(dbkey, *names)
      end
      private :remove_stale_nil_fields

      # Persists the object's data to storage within a transaction.
      #
      # This is the primary code path that adds an object to the class-level
      # +instances+ sorted set (step 4). The +commit_fields+ method also
      # touches instances via +touch_instances!+. Any persistence that bypasses
      # both of these (e.g. +update_fields+, or raw +hmset+) will create a
      # hash key in the DB that is invisible to +instances.to_a+ and any
      # code that enumerates via the instances collection.
      #
      # This method contains the core persistence logic shared by both save and
      # save_if_not_exists. It must be called within a transaction block.
      #
      # @param update_expiration [Boolean] Whether to update the key's expiration
      # @param tracked_index_scopes [Hash] instance-scoped index tracker
      #   entries, pre-read outside the transaction by the caller (the read
      #   cannot happen here -- HGETALL inside MULTI returns futures). Only
      #   +save+ and +save_if_not_exists!+ supply it; the +atomic_write+ paths
      #   call this from inside a MULTI they already opened, so there is no
      #   pre-transaction point available to them and they default to empty,
      #   leaving instance-scoped indexes untouched.
      # @param prune_stale_tracker [Boolean] true when the caller determined
      #   the tracker entries belong to a dead incarnation of this identifier
      #   (object hash absent while entries survive -- delete! or expiry).
      #   Stale entries are pruned via remove_from_* replay instead of being
      #   re-joined onto the record being written (#365).
      # @return [Object] The result of the hmset operation
      #
      def persist_to_storage(update_expiration, tracked_index_scopes: {}, prune_stale_tracker: false)
        # 1. Save all non-nil fields to hashkey at once
        prepared_h = to_h_for_storage
        hmset_result = hmset(prepared_h)

        # 1b. Remove any fields cleared to nil so a nil'd value does not linger
        # in storage. HMSET only sets the fields it is given; it never deletes
        # omitted ones, so an update that clears a field to nil would otherwise
        # leave the prior value behind. Harmless no-op on the create path.
        remove_stale_nil_fields

        # 2. Set expiration in same transaction
        self.update_expiration if update_expiration

        # 3. Update class-level indexes
        auto_update_class_indexes

        # 3b. Reconcile instance-scoped indexes using the tracker snapshot
        # read before this transaction opened. Live entries (the object hash
        # existed) are refreshed for scopes already registered via add_to_*;
        # the initial add_to_* remains manual. Stale entries -- left by a
        # previous incarnation whose hash was delete!'d or expired -- are
        # pruned instead, removing that incarnation's index buckets and the
        # tracker itself rather than joining its scopes (#365).
        if prune_stale_tracker
          remove_tracked_index_entries!(tracked_index_scopes) if respond_to?(:remove_tracked_index_entries!)
        elsif respond_to?(:auto_update_instance_indexes)
          auto_update_instance_indexes(tracked_index_scopes)
        end

        # 4. Touch instances timeline (delegates to touch_instances!).
        #
        # Skip it when there is genuinely nothing stored and no hash key exists.
        # prepared_h is empty only when every declared persistent field is nil
        # AND the identifier is not itself a stored field (a Proc-derived
        # identifier) -- hmset no-op'd and no key was created. Registering the
        # identifier in `instances` in that case would leave a dangling
        # reference: the identifier would list in instances.to_a while exists?
        # (check_size: true) returns false and any load follows a dead pointer.
        # In the ubiquitous `identifier_field :id; field :id` pattern the id
        # keeps prepared_h non-empty, so this only skips the degenerate case.
        touch_instances! unless prepared_h.empty?

        hmset_result
      end
      private :persist_to_storage
    end
  end
end
