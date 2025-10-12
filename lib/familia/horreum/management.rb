# lib/familia/horreum/management.rb

module Familia
  class Horreum
    # ManagementMethods - Class-level methods for Horreum model management
    #
    # This module is extended into classes that include Familia::Horreum,
    # providing class methods for database operations and object management
    # (e.g., Customer.create, Customer.find_by_id)
    #
    # # Key features:
    # * Includes RelatedFieldsManagement for DataType field handling
    # * Provides utility methods for working with Database objects
    #
    module ManagementMethods
      include Familia::Horreum::RelatedFieldsManagement # Provides DataType query methods

      using Familia::Refinements::StylizeWords

      # Creates and persists a new instance of the class.
      #
      # @param args [Array] Variable number of positional arguments to be passed
      #   to the constructor.
      # @param kwargs [Hash] Keyword arguments to be passed to the constructor.
      # @return [Object] The newly created and persisted instance.
      # @raise [Familia::RecordExistsError] If an instance with the same identifier already
      #   exists.
      #
      # This method serves as a factory method for creating and persisting new
      # instances of the class. It combines object instantiation, existence
      # checking, and persistence in a single operation.
      #
      # The method is flexible in accepting both positional and keyword arguments:
      # - Positional arguments (*args) are passed directly to the constructor.
      # - Keyword arguments (**kwargs) are passed as a hash to the constructor.
      #
      # After instantiation, the method checks if an object with the same
      # identifier already exists. If it does, a Familia::RecordExistsError exception is
      # raised to prevent overwriting existing data.
      #
      # Finally, the method saves the new instance returns it.
      #
      # @example Creating an object with keyword arguments
      #   User.create(name: "John", age: 30)
      #
      # @example Creating an object with positional and keyword arguments (not recommended)
      #   Product.create("SKU123", name: "Widget", price: 9.99)
      #
      # @note The behavior of this method depends on the implementation of #new,
      #   #exists?, and #save in the class and its superclasses.
      #
      # @see #new
      # @see #exists?
      # @see #save
      def create!(...)
        hobj = new(...)
        hobj.save_if_not_exists!

        # If a block is given, yield the created object
        # This allows for additional operations on successful creation
        yield hobj if block_given?

        hobj
      end

      def multiget(...)
        rawmultiget(...).filter_map { |json| Familia::JsonSerializer.parse(json) }
      end

      def rawmultiget(*hids)
        hids.collect! { |hobjid| dbkey(hobjid) }
        return [] if hids.compact.empty?

        Familia.trace :MULTIGET, nil, "#{hids.size}: #{hids}" if Familia.debug?
        dbclient.mget(*hids)
      end

      # Converts the class name into a string that can be used to look up
      # configuration values. This is particularly useful when mapping
      # familia models with specific database numbers in the configuration.
      #
      # Familia::Horreum::DefinitionMethods#config_name
      #
      # @example V2::Session.config_name => 'session'
      #
      # @return [String] The underscored class name as a string
      def config_name
        return nil if name.nil?

        name.demodularize.snake_case
      end

      # Familia::Horreum::DefinitionMethods#familia_name
      #
      # @example V2::Session.config_name => 'Session'
      #
      def familia_name
        return nil if name.nil?

        name.demodularize
      end

      # Retrieves and instantiates an object from Database using the full object
      # key.
      #
      # @param objkey [String] The full dbkey for the object.
      # @return [Object, nil] An instance of the class if the key exists, nil
      #   otherwise.
      # @raise [ArgumentError] If the provided key is empty.
      #
      # This method performs a two-step process to safely retrieve and
      # instantiate objects:
      #
      # 1. It first checks if the key exists in the database. This is crucial because:
      #    - It provides a definitive answer about the object's existence.
      #    - It prevents ambiguity that could arise from `hgetall` returning an
      #      empty hash for non-existent keys, which could lead to the creation
      #      of "empty" objects.
      #
      # 2. If the key exists, it retrieves the object's data and instantiates
      #    it.
      #
      # This approach ensures that we only attempt to instantiate objects that
      # actually exist in Valkey/Redis, improving reliability and simplifying
      # debugging.
      #
      # @example
      #   User.find_by_key("user:123")  # Returns a User instance if it exists,
      #   nil otherwise
      #
      def find_by_dbkey(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        # We use a lower-level method here b/c we're working with the
        # full key and not just the identifier.
        does_exist = dbclient.exists(objkey).positive?

        Familia.ld "[find_by_key] #{self} from key #{objkey} (exists: #{does_exist})"
        Familia.trace :FIND_BY_DBKEY_KEY, nil, objkey

        # This is the reason for calling exists first. We want to definitively
        # and without any ambiguity know if the object exists in the database. If it
        # doesn't, we return nil. If it does, we proceed to load the object.
        # Otherwise, hgetall will return an empty hash, which will be passed to
        # the constructor, which will then be annoying to debug.
        return unless does_exist

        obj = dbclient.hgetall(objkey) # horreum objects are persisted as database hashes
        Familia.trace :FIND_BY_DBKEY_INSPECT, nil, "#{objkey}: #{obj.inspect}"

        # Create instance and deserialize fields using existing helper method
        # This avoids duplicating deserialization logic and keeps field-by-field processing
        instance = allocate
        instance.send(:initialize_relatives)
        instance.send(:initialize_with_keyword_args_deserialize_value, **obj)
        instance
      end
      alias find_by_key find_by_dbkey

      # Retrieves and instantiates an object from Database using its identifier.
      #
      # @param identifier [String, Integer] The unique identifier for the
      #   object.
      # @param suffix [Symbol] The suffix to use in the dbkey (default:
      #   :object).
      # @return [Object, nil] An instance of the class if found, nil otherwise.
      #
      # This method constructs the full dbkey using the provided identifier
      # and suffix, then delegates to `find_by_key` for the actual retrieval and
      # instantiation.
      #
      # It's a higher-level method that abstracts away the key construction,
      # making it easier to retrieve objects when you only have their
      # identifier.
      #
      # @example
      #   User.find_by_id(123)  # Equivalent to User.find_by_key("user:123:object")
      #
      def find_by_identifier(identifier, suffix = nil)
        suffix ||= self.suffix
        return nil if identifier.to_s.empty?

        objkey = dbkey(identifier, suffix)

        Familia.ld "[find_by_id] #{self} from key #{objkey})"
        Familia.trace :FIND_BY_ID, nil, objkey if Familia.debug?
        find_by_dbkey objkey
      end
      alias find_by_id find_by_identifier
      alias find find_by_id
      alias load find_by_id

      # Checks if an object with the given identifier exists in the database.
      #
      # @param identifier [String, Integer] The unique identifier for the object.
      # @param suffix [Symbol, nil] The suffix to use in the dbkey (default: class suffix).
      # @return [Boolean] true if the object exists, false otherwise.
      #
      # This method constructs the full dbkey using the provided identifier and suffix,
      # then checks if the key exists in the database.
      #
      # @example
      #   User.exists?(123)  # Returns true if user:123:object exists in Valkey/Redis
      #
      def exists?(identifier, suffix = nil)
        raise NoIdentifier, 'Empty identifier' if identifier.to_s.empty?

        suffix ||= self.suffix

        objkey = dbkey identifier, suffix

        ret = dbclient.exists objkey
        Familia.trace :EXISTS, nil, "#{objkey} #{ret.inspect}" if Familia.debug?

        # Handle Redis::Future objects during transactions
        return ret if ret.is_a?(Redis::Future)

        ret.positive? # differs from Valkey API but I think it's okay bc `exists?` is a predicate method.
      end

      # Destroys an object in Database with the given identifier.
      #
      # @param identifier [String, Integer] The unique identifier for the object to destroy.
      # @param suffix [Symbol, nil] The suffix to use in the dbkey (default: class suffix).
      # @return [Boolean] true if the object was successfully destroyed, false otherwise.
      #
      # This method is part of Familia's high-level object lifecycle management. While `delete!`
      # operates directly on dbkeys, `destroy!` operates at the object level and is used for
      # ORM-style operations. Use `destroy!` when removing complete objects from the system, and
      # `delete!` when working directly with dbkeys.
      #
      # @example
      #   User.destroy!(123)  # Removes user:123:object from Valkey/Redis
      #
      def destroy!(identifier, suffix = nil)
        suffix ||= self.suffix
        return MultiResult.new(false, []) if identifier.to_s.empty?

        objkey = dbkey identifier, suffix

        # Execute all deletion operations within a transaction
        transaction do |conn|
          # Clean up related fields first to avoid orphaned keys
          if relations?
            Familia.trace :DESTROY_RELATIONS!, nil, "#{self} has relations: #{related_fields.keys}" if Familia.debug?

            # Create a temporary instance to access related fields.
            # Pass identifier in constructor so init() sees it and can set dependent fields.
            identifier_field_name = self.identifier_field
            temp_instance = identifier_field_name ? new(identifier_field_name => identifier.to_s) : new

            related_fields.each do |name, _definition|
              obj = temp_instance.send(name)
              Familia.trace :DESTROY_RELATION!, name, "Deleting related field #{name} (#{obj.dbkey})" if Familia.debug?
              conn.del(obj.dbkey)
            end
          end

          # Delete the main object key
          ret = conn.del(objkey)
          Familia.trace :DESTROY!, nil, "#{objkey} #{ret.inspect}" if Familia.debug?
        end
      end

      # Finds all keys in Database matching the given suffix pattern.
      #
      # @param suffix [String] The suffix pattern to match (default: '*').
      # @return [Array<String>] An array of matching dbkeys.
      #
      # This method searches for all dbkeys that match the given suffix pattern.
      # It uses the class's dbkey method to construct the search pattern.
      #
      # @example
      #   User.find  # Returns all keys matching user:*:object
      #   User.find('active')  # Returns all keys matching user:*:active
      #
      def find_keys(suffix = '*')
        dbclient.keys(dbkey('*', suffix)) || []
      end

      # +identifier+ can be a value or an Array of values used to create the index.
      # We don't enforce a default suffix; that's left up to the instance.
      # The suffix is used to differentiate between different types of objects.
      #
      # +suffix+ If a nil value is explicitly passed in, it won't appear in the redis
      # key that's returned. If no suffix is passed in, the class' suffix is used
      # as the default (via the class method self.suffix). It's an important
      # distinction b/c passing in an explicitly nil is how DataType objects
      # at the class level are created without the global default 'object'
      # suffix. See DataType#dbkey "parent_class?" for more details.
      #
      def dbkey(identifier, suffix = self.suffix)
        if identifier.to_s.empty?
          raise NoIdentifier, "#{self} requires non-empty identifier, got: #{identifier.inspect}"
        end

        identifier &&= identifier.to_s
        Familia.dbkey(prefix, identifier, suffix)
      end

      def all(suffix = nil)
        suffix ||= self.suffix
        # objects that could not be parsed will be nil
        keys(suffix).filter_map { |k| find_by_key(k) }
      end

      def any?(filter = '*')
        matching_keys_count(filter).positive?
      end

      # Returns the number of dbkeys matching the given filter pattern
      # @param filter [String] dbkey pattern to match (default: '*')
      # @return [Integer] Number of matching keys
      #
      def matching_keys_count(filter = '*')
        dbclient.keys(dbkey(filter)).compact.size
      end
      alias size matching_keys_count
      alias length matching_keys_count
    end
  end
end
