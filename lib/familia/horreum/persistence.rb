# lib/familia/horreum/persistence.rb

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
      # Persists the object to Valkey storage with automatic timestamping and validation.
      #
      # Saves the current object state to Valkey storage, automatically setting
      # created and updated timestamps if the object supports them. The method
      # validates unique indexes before the transaction, commits all persistent
      # fields, and optionally updates the key's expiration.
      #
      # @param update_expiration [Boolean] Whether to update the key's expiration
      #   time after saving. Defaults to true.
      #
      # @return [Boolean] true if the save operation was successful, false otherwise.
      #
      # @raise [Familia::OperationModeError] If called within an existing transaction.
      #   Guards need to read current values, which is not possible inside MULTI/EXEC.
      # @raise [Familia::RecordExistsError] If a unique index constraint is violated
      #   for any class-level unique_index relationships.
      #
      # @example Save an object to Valkey
      #   user = User.new(name: "John", email: "john@example.com")
      #   user.save
      #   # => true
      #
      # @example Save without updating expiration
      #   user.save(update_expiration: false)
      #   # => true
      #
      # @example Handle duplicate unique index
      #   user2 = User.new(name: "Jane", email: "john@example.com")
      #   user2.save
      #   # => raises Familia::RecordExistsError
      #
      # @note Cannot be called within a transaction. Call save first to start
      #   the transaction, or use commit_fields/hmset for manual field updates
      #   within transactions.
      #
      # @note When Familia.debug? is enabled, this method will trace the save
      #   operation for debugging purposes.
      #
      # @see #commit_fields The underlying method that performs the field persistence
      # @see #guard_unique_indexes! Automatic validation of class-level unique indexes
      #
      def save(update_expiration: true)
        # Prevent save within transaction or pipeline - guards need to read current values
        if Fiber[:familia_transaction]
          raise Familia::OperationModeError,
            "Cannot call save within a transaction. Call save first to start the transaction."
        end

        Familia.trace :SAVE, nil, self.class.uri if Familia.debug?

        # Update timestamp fields before saving
        self.created ||= Familia.now if respond_to?(:created)
        self.updated = Familia.now if respond_to?(:updated)

        # Validate unique indexes BEFORE the transaction
        guard_unique_indexes!

        # Everything in ONE transaction for complete atomicity
        result = transaction do |_conn|
          # 1. Save all fields
          prepared_h = to_h_for_storage
          hmset_result = hmset(prepared_h)

          # 2. Set expiration in same transaction
          self.update_expiration if update_expiration

          # 3. Update class-level indexes
          auto_update_class_indexes

          # 4. Add to instances collection if available
          self.class.instances.add(identifier, Familia.now) if self.class.respond_to?(:instances)

          hmset_result
        end

        Familia.ld "[save] #{self.class} #{dbkey} #{result} (update_expiration: #{update_expiration})"

        # Return boolean indicating success
        !result.nil?
      end

      # Saves the object to Valkey storage only if it doesn't already exist.
      #
      # Conditionally persists the object to Valkey storage by first checking if the
      # identifier field already exists. If the object already exists in storage,
      # raises an error. Otherwise, proceeds with a normal save operation including
      # automatic timestamping.
      #
      # This method provides atomic conditional creation to prevent duplicate objects
      # from being saved when uniqueness is required based on the identifier field.
      #
      # @param update_expiration [Boolean] Whether to update the key's expiration
      #   time after saving. Defaults to true.
      #
      # @return [Boolean] true if the save operation was successful
      #
      # @raise [Familia::RecordExistsError] If an object with the same identifier
      #   already exists in Valkey storage
      #
      # @example Save a new user only if it doesn't exist
      #   user = User.new(id: 123, name: "John")
      #   user.save_if_not_exists
      #   # => true (saved successfully)
      #
      # @example Attempting to save an existing object
      #   existing_user = User.new(id: 123, name: "Jane")
      #   existing_user.save_if_not_exists
      #   # => raises Familia::RecordExistsError
      #
      # @example Save without updating expiration
      #   user.save_if_not_exists(update_expiration: false)
      #   # => true
      #
      # @note This method uses HSETNX to atomically check and set the identifier
      #   field, ensuring race-condition-free conditional creation.
      #
      # @see #save The underlying save method called when the object doesn't exist
      #
      # Check if save_if_not_exists is implemented correctly. It should:
      #
      # Check if record exists
      # If exists, raise Familia::RecordExistsError
      # If not exists, save
      def save_if_not_exists!(update_expiration: true)
        identifier_field = self.class.identifier_field

        Familia.ld "[save_if_not_exists]: #{self.class} #{identifier_field}=#{identifier}"
        Familia.trace :SAVE_IF_NOT_EXISTS, nil, self.class.uri if Familia.debug?

        attempts = 0
        begin
          attempts += 1

          watch do
            raise Familia::RecordExistsError, dbkey if exists?

            txn_result = transaction do |_multi|
              hmset(to_h_for_storage)

              self.update_expiration if update_expiration

              # Auto-index for class-level indexes after successful save
              auto_update_class_indexes
            end

            Familia.ld "[save_if_not_exists]: txn_result=#{txn_result.inspect}"

            txn_result.successful?
          end
        rescue OptimisticLockError => e
          Familia.ld "[save_if_not_exists]: OptimisticLockError (#{attempts}): #{e.message}"
          raise if attempts >= 3

          sleep(0.001 * (2**attempts))
          retry
        end
      end

      def save_if_not_exists(...)
        save_if_not_exists!(...)
      rescue RecordExistsError, OptimisticLockError
        false
      end

      # Commits object fields to the DB storage.
      #
      # Persists the current state of all object fields to the DB using HMSET.
      # Optionally updates the key's expiration time if the feature is enabled
      # for the object's class.
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
      def commit_fields(update_expiration: true)
        prepared_value = to_h_for_storage
        Familia.ld "[commit_fields] Begin #{self.class} #{dbkey} #{prepared_value} (exp: #{update_expiration})"

        transaction do |_conn|
          # Set all fields atomically
          result = hmset(prepared_value)

          # Update expiration in same transaction to ensure atomicity
          self.update_expiration if result && update_expiration

          result
        end
      end

      # Updates multiple fields atomically in a Database transaction.
      #
      # @param kwargs [Hash] Field names and values to update. Special key :update_expiration
      #   controls whether to update key expiration (default: true)
      # @return [MultiResult] Transaction result
      #
      # @example Update multiple fields without affecting expiration
      #   metadata.batch_update(viewed: 1, updated: Time.now.to_i, update_expiration: false)
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
        end
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
      # Deletes the object's database key and all associated data. This operation
      # is irreversible and will permanently destroy all stored information
      # for this object instance and the additional list, set, hash, string
      # etc fields defined for this class.
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
        transaction do |_conn|
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
        end
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
        Familia.ld "[refresh!] #{self.class} #{dbkey} fields:#{fields.keys}"

        # Reset transient fields to nil for semantic clarity and ORM consistency
        # Transient fields have no authoritative source, so they should return to
        # their uninitialized state during refresh operations
        reset_transient_fields!

        naive_refresh(**fields)
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
          Familia.ld "[reset_transient_fields!] Reset #{field_name} to nil"
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
        # Skip validation if we're already in a transaction (can't read values)
        return if Fiber[:familia_transaction]

        return unless self.class.respond_to?(:indexing_relationships)

        self.class.indexing_relationships.each do |rel|
          # Only validate unique indexes (not multi_index)
          next unless rel.cardinality == :unique

          # Only validate class-level indexes
          next unless rel.target_class == self.class

          # Call the validation method if it exists
          validate_method = :"guard_unique_#{rel.index_name}!"
          send(validate_method) if respond_to?(validate_method)
        end
      end

      # Automatically update class-level indexes after save
      #
      # Iterates through class-level indexing relationships and calls their
      # corresponding add_to_class_* methods to populate indexes. Only processes
      # class-level indexes (where target_class == self.class), skipping
      # instance-scoped indexes which require parent context.
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
          # Skip instance-scoped indexes (require parent context)
          # Instance-scoped indexes must be manually populated because they need
          # the parent object reference (e.g., employee.add_to_company_badge_index(company))
          unless rel.target_class == self.class
            Familia.ld <<~LOG_MESSAGE
              [auto_update_class_indexes] Skipping #{rel.index_name} (requires parent context)
            LOG_MESSAGE
            next
          end

          # Call the existing add_to_class_* methods
          add_method = :"add_to_class_#{rel.index_name}"
          send(add_method) if respond_to?(add_method)
        end
      end
    end
  end
end
