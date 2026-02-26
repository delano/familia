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

        # Everything in ONE transaction for complete atomicity
        result = transaction do |_conn|
          persist_to_storage(update_expiration)
        end

        # Structured lifecycle logging and instrumentation
        if Familia.debug? && start_time
          duration = Familia.now_in_μs - start_time

          begin
            fields_count = to_h_for_storage.size
          rescue => e
            Familia.error "Failed to serialize fields for logging",
              error: e.message,
              class: self.class.name,
              identifier: (identifier rescue nil)
            fields_count = 0
          end

          Familia.debug "Horreum saved",
            class: self.class.name,
            identifier: identifier,
            duration: duration,
            fields_count: fields_count,
            update_expiration: update_expiration

          Familia::Instrumentation.notify_lifecycle(:save, self,
            duration: duration,
            update_expiration: update_expiration,
            fields_count: fields_count
          )
        end

        # Clear dirty tracking after successful save
        clear_dirty! unless result.nil?

        # Return boolean indicating success
        !result.nil?
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
      #
      def save_with_collections(update_expiration: true)
        saved = save(update_expiration: update_expiration)
        yield if saved && block_given?
        saved
      end

      # Conditionally persists object only if it doesn't already exist in storage.
      #
      # Uses optimistic locking (WATCH) to atomically check existence and save.
      # If the object doesn't exist, performs identical operations as save.
      # If it exists, raises an error with retry logic for optimistic lock failures.
      #
      # `save_if_not_exists` doesn't call save because of the gap between checking
      # existence and persisting the data. We can't check for existence inside the
      # transaction because commands are queued and not executed until EXEC
      # is called (if you try you get a Redis::Future object). So here we use a
      # WATCH + MULTI/EXEC pattern to fail the transaction if the key is created
      # (or modified in any way) to avoid silent data corruption♀︎.

      # ♀︎ Additional note about WATCH + MULTI/EXEC in Valkey/Redis or any two
      # step existence check in any database: although it is more cautious,
      # it is not atomic. The only way to do that is if the database process
      # can determine itself whether the record already exists or not. For
      # Valkey/Redis, that means writing the lua to do that.
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

        attempts = 0
        begin
          attempts += 1

          result = watch do
            raise Familia::RecordExistsError, dbkey if exists?

            txn_result = transaction do |_multi|
              persist_to_storage(update_expiration)
            end

            Familia.debug "[save_if_not_exists]: txn_result=#{txn_result.inspect}"

            txn_result
          end

          Familia.debug "[save_if_not_exists]: result=#{result.inspect}"

          # Clear dirty tracking after successful save
          clear_dirty! unless result.nil?

          # Return boolean indicating success (consistent with save method)
          !result.nil?
        rescue OptimisticLockError => e
          Familia.debug "[save_if_not_exists]: OptimisticLockError (#{attempts}): #{e.message}"
          raise if attempts >= 3

          sleep(0.001 * (2**attempts))
          retry
        end
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
      # Unlike +save+, this method does NOT add the object to the class-level
      # +instances+ sorted set, does not run +prepare_for_save+ (timestamps,
      # unique index guards), and does not update class indexes. Use this for
      # updating fields on an object that is already persisted and tracked.
      # If the object's hash key was created via +commit_fields+ alone, it
      # will exist in the DB but won't appear in +instances.to_a+ listings.
      #
      # @param update_expiration [Boolean] Whether to update the expiration time
      #   of the Valkey key. Defaults to true.
      #
      # @return [Object] The result of the HMSET operation from the DB.
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

        result = transaction do |_conn|
          # Set all fields atomically
          result = hmset(prepared_value)

          # Update expiration in same transaction to ensure atomicity
          self.update_expiration if result && update_expiration

          # Register in instances sorted set so the object is visible
          # to list-based enumeration (instances.to_a, count, etc.)
          ensure_registered! if result

          result
        end

        # Clear dirty tracking after successful commit
        clear_dirty! unless result.nil?

        result
      end

      # Updates multiple fields atomically in a Database transaction.
      #
      # @param kwargs [Hash] Field names and values to update. Special key :update_expiration
      #   controls whether to update key expiration (default: true)
      # @return [MultiResult] Transaction result
      #
      # @example Update multiple fields without affecting expiration
      #   metadata.batch_update(viewed: 1, updated: Familia.now.to_i, update_expiration: false)
      #
      # @example Update fields with expiration refresh
      #   user.batch_update(name: "John", email: "john@example.com")
      #
      def batch_update(**kwargs)
        update_expiration = kwargs.delete(:update_expiration) { true }
        fields = kwargs

        Familia.trace :BATCH_UPDATE, nil, fields.keys if Familia.debug?

        transaction do |_conn|
          # 1. Update all fields atomically
          fields.each do |field, value|
            prepared_value = serialize_value(value)
            hset field, prepared_value
            # Update instance variable to keep object in sync
            send("#{field}=", value) if respond_to?("#{field}=")
          end

          # 2. Update expiration in same transaction
          self.update_expiration if update_expiration

          # 3. Register in instances sorted set so the object is visible
          # to list-based enumeration (instances.to_a, count, etc.)
          ensure_registered!
        end
      end

      # Atomically writes multiple fields to the database using a single HMSET.
      #
      # This is the multi-field equivalent of the fast_writer (!) methods.
      # It sets all instance variables, serializes the values, and persists
      # them in one HMSET command within a transaction. More efficient than
      # batch_update (which does individual HSET per field) when writing
      # several fields at once.
      #
      # @param kwargs [Hash] Field names and values to write. Special key
      #   :update_expiration controls whether to refresh key expiration
      #   (default: true).
      # @return [self] Returns self for method chaining
      #
      # @example Persist multiple fields atomically
      #   user.batch_fast_write(name: "Jane", email: "jane@example.com")
      #
      # @example Without updating expiration
      #   user.batch_fast_write(status: "active", update_expiration: false)
      #
      # @see #batch_update Similar but uses individual HSET per field
      # @see #save_fields Persists current in-memory values of named fields
      #
      def batch_fast_write(**kwargs)
        update_exp = kwargs.delete(:update_expiration) { true }
        fields = kwargs

        raise ArgumentError, 'No fields specified' if fields.empty?

        Familia.trace :BATCH_FAST_WRITE, nil, fields.keys if Familia.debug?

        # Build serialized hash and update instance variables
        serialized = {}
        fields.each do |field, value|
          send(:"#{field}=", value) if respond_to?(:"#{field}=")
          serialized[field] = serialize_value(value)
        end

        transaction do |_conn|
          hmset(serialized)

          self.update_expiration if update_exp

          ensure_registered!
        end

        self
      end

      # Persists only the specified fields to Redis.
      #
      # Saves the current in-memory values of specified fields to Redis without
      # modifying them first. Fields must already be set on the instance.
      #
      # @param field_names [Array<Symbol, String>] Names of fields to persist
      # @param update_expiration [Boolean] Whether to refresh key expiration
      # @return [self] Returns self for method chaining
      #
      # @example Persist only passphrase fields after updating them
      #   customer.update_passphrase('secret').save_fields(:passphrase, :passphrase_encryption)
      #
      def save_fields(*field_names, update_expiration: true)
        raise ArgumentError, 'No fields specified' if field_names.empty?

        Familia.trace :SAVE_FIELDS, nil, field_names if Familia.debug?

        transaction do |_conn|
          # Build hash of field names to serialized values
          fields_hash = {}
          field_names.each do |field|
            field_sym = field.to_sym
            raise ArgumentError, "Unknown field: #{field}" unless respond_to?(field_sym)

            value = send(field_sym)
            prepared_value = serialize_value(value)
            fields_hash[field] = prepared_value
          end

          # Set all fields at once using hmset
          hmset(fields_hash)

          # Update expiration in same transaction
          self.update_expiration if update_expiration

          # Register in instances sorted set so the object is visible
          # to list-based enumeration (instances.to_a, count, etc.)
          ensure_registered!
        end

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
        fields.each do |field, value|
          # Apply the field value if the setter method exists
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
        Familia.trace :DESTROY!, dbkey, self.class.uri

        # Execute all deletion operations within a transaction
        result = transaction do |_conn|
          # Delete the main object key
          delete!

          # Delete all related fields if present
          if self.class.relations?
            Familia.trace :DELETE_RELATED_FIELDS!, nil,
                          "#{self.class} has relations: #{self.class.related_fields.keys}"

            self.class.related_fields.each_key do |name|
              obj = send(name)
              Familia.trace :DELETE_RELATED_FIELD, name, "Deleting related field #{name} (#{obj.dbkey})"
              obj.delete!
            end
          end

          # Remove from instances collection
          unregister!
        end

        # Structured lifecycle logging and instrumentation
        Familia.debug "Horreum destroyed",
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

      # Ensures this object is registered in the class-level instances sorted set.
      #
      # This is the foundational primitive for all registry-aware code paths.
      # It delegates to ZADD which is naturally idempotent: if the identifier
      # is already present the score (timestamp) is updated; if absent, it is
      # added. No preliminary member? check is performed, making this safe to
      # call inside MULTI/EXEC transactions where read operations return
      # uninspectable Future objects.
      #
      # @return [Object] The return value of the ZADD command (boolean or
      #   Redis::Future inside a transaction)
      #
      # @raise [Familia::NoIdentifier] if the identifier is nil or empty
      #
      # @example Register an object that was created via commit_fields
      #   user.commit_fields
      #   user.ensure_registered!  # now visible in User.instances
      #
      # @example Safe to call multiple times (updates timestamp)
      #   user.ensure_registered!
      #   user.ensure_registered!  # score updated, no duplicate
      #
      def ensure_registered!
        ident = identifier
        raise Familia::NoIdentifier, "No identifier for #{self.class}" if ident.nil? || ident.to_s.empty?

        self.class.instances.add(self, Familia.now)
      end

      # Removes this object from the class-level instances sorted set.
      #
      # Symmetric counterpart to {#ensure_registered!}. After calling this
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
      # @example Remove from registry without deleting data
      #   user.unregister!  # no longer in User.instances
      #   user.exists?      # => true (hash key still present)
      #
      # @see #ensure_registered! The symmetric add operation
      # @see #destroy! Full object removal (data + registry)
      #
      def unregister!
        ident = identifier
        raise Familia::NoIdentifier, "No identifier for #{self.class}" if ident.nil? || ident.to_s.empty?

        self.class.instances.remove(ident)
      end

      # Convenience methods that forward to the class method of the same name
      def transaction(...) = self.class.transaction(...)
      def pipelined(...) = self.class.pipelined(...)
      def dbclient(...) = self.class.dbclient(...)

      private

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
      def guard_unique_indexes!
        return unless self.class.respond_to?(:indexing_relationships)

        self.class.indexing_relationships.each do |rel|
          # Only validate unique indexes (not multi_index)
          next unless rel.cardinality == :unique

          # Only validate class-level indexes (skip instance-scoped)
          next if rel.within

          # Call the validation method if it exists
          validate_method = :"guard_unique_#{rel.index_name}!"
          send(validate_method) if respond_to?(validate_method)
        end

        nil # Explicit nil return as documented
      end

      # Automatically update class-level indexes after save
      #
      # Iterates through class-level indexing relationships and calls their
      # corresponding add_to_class_* methods to populate indexes. Only processes
      # class-level indexes (where within is nil), skipping instance-scoped
      # indexes which require scope context.
      #
      # Uses idempotent Redis commands (HSET for unique_index) so repeated calls
      # are safe and have negligible performance overhead. Note that multi_index
      # always requires within: parameter, so only unique_index benefits from this.
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
      #   customer.save  # Automatically calls add_to_class_email_lookup
      #
      # @note Only class-level unique_index declarations auto-populate.
      #   Instance-scoped indexes (with within:) require manual population:
      #   employee.add_to_company_badge_index(company)
      #
      # @see Familia::Features::Relationships::Indexing For index declaration details
      #
      def auto_update_class_indexes
        return unless self.class.respond_to?(:indexing_relationships)

        self.class.indexing_relationships.each do |rel|
          # Skip instance-scoped indexes (require scope context)
          # Instance-scoped indexes must be manually populated because they need
          # the scope instance reference (e.g., employee.add_to_company_badge_index(company))
          #
          # Class-level indexes have within: nil (unique_index) or within: :class (multi_index)
          # Instance-scoped indexes have within: SomeClass (a specific class)
          if rel.within && rel.within != :class
            Familia.debug <<~LOG_MESSAGE
              [auto_update_class_indexes] Skipping #{rel.index_name} (requires scope context)
            LOG_MESSAGE
            next
          end

          # Call the existing add_to_class_* methods
          add_method = :"add_to_class_#{rel.index_name}"
          send(add_method) if respond_to?(add_method)
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

        # Validate unique indexes BEFORE the transaction
        guard_unique_indexes!
      end
      private :prepare_for_save

      # Persists the object's data to storage within a transaction.
      #
      # This is the primary code path that adds an object to the class-level
      # +instances+ sorted set (step 4). The +commit_fields+ method also
      # registers via +ensure_registered!+. Any persistence that bypasses
      # both of these (e.g. +update_fields+, or raw +hmset+) will create a
      # hash key in the DB that is invisible to +instances.to_a+ and any
      # code that enumerates via the instances collection.
      #
      # This method contains the core persistence logic shared by both save and
      # save_if_not_exists. It must be called within a transaction block.
      #
      # @param update_expiration [Boolean] Whether to update the key's expiration
      # @return [Object] The result of the hmset operation
      #
      def persist_to_storage(update_expiration)
        # 1. Save all fields to hashkey at once
        prepared_h = to_h_for_storage
        hmset_result = hmset(prepared_h)

        # 2. Set expiration in same transaction
        self.update_expiration if update_expiration

        # 3. Update class-level indexes
        auto_update_class_indexes

        # 4. Register in instances collection (delegates to ensure_registered!)
        ensure_registered!

        hmset_result
      end
      private :persist_to_storage
    end
  end
end
