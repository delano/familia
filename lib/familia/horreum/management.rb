# lib/familia/horreum/management.rb
#
# frozen_string_literal: true

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

      # Retrieves and deserializes multiple objects by their identifiers using MGET.
      #
      # @param hids [Array<String, Integer>] Variable number of object identifiers to retrieve.
      # @return [Array<Object>] Array of deserialized objects, with nils filtered out.
      #
      # This method fetches multiple JSON-serialized values from Redis in a single MGET
      # command and deserializes them. It's useful for bulk retrieval of simple string
      # values (not hashes) stored as JSON.
      #
      # @example Retrieve multiple objects by ID
      #   Customer.multiget('cust_123', 'cust_456', 'cust_789')
      #   #=> [<Customer>, <Customer>, <Customer>]
      #
      # @note This method filters out nil values from the result. If you need to preserve
      #   position alignment with input identifiers, use {#rawmultiget} instead.
      # @note This is for string values stored as JSON, not hash objects. For hash objects,
      #   use {#load_multi} instead.
      #
      # @see #rawmultiget For raw JSON strings without deserialization
      # @see #load_multi For loading hash-based Horreum objects
      #
      def multiget(...)
        rawmultiget(...).filter_map { |json| Familia::JsonSerializer.parse(json) }
      end

      # Retrieves raw JSON strings for multiple objects by their identifiers using MGET.
      #
      # @param hids [Array<String, Integer>] Variable number of object identifiers to retrieve.
      # @return [Array<String, nil>] Array of raw JSON strings (or nils for non-existent keys).
      #
      # This is a lower-level method that fetches multiple values from Redis without
      # deserializing them. It converts identifiers to full dbkeys and executes a single
      # MGET command.
      #
      # @example Retrieve raw JSON for multiple objects
      #   Customer.rawmultiget('cust_123', 'cust_456')
      #   #=> ['{"name":"Alice"}', '{"name":"Bob"}']
      #
      # @example Handle non-existent keys
      #   Customer.rawmultiget('exists', 'missing')
      #   #=> ['{"name":"Alice"}', nil]
      #
      # @note Returns an empty array if all identifiers are empty or nil.
      # @note Position in result array corresponds to position in input array.
      #
      # @see #multiget For deserialized objects with nils filtered out
      #
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
      # @param check_exists [Boolean] Whether to check key existence before HGETALL
      #   (default: true). When false, skips EXISTS check for better performance
      #   but still returns nil for non-existent keys (detected via empty hash).
      # @return [Object, nil] An instance of the class if the key exists, nil
      #   otherwise.
      # @raise [ArgumentError] If the provided key is empty.
      #
      # This method can operate in two modes:
      #
      # **Safe mode (check_exists: true, default):**
      # 1. First checks if the key exists with EXISTS command
      # 2. Returns nil immediately if key doesn't exist
      # 3. If exists, retrieves data with HGETALL and instantiates object
      # - Best for: Single object lookups, defensive code
      # - Commands: 2 per object (EXISTS + HGETALL)
      #
      # **Optimized mode (check_exists: false):**
      # 1. Directly calls HGETALL without EXISTS check
      # 2. Returns nil if HGETALL returns empty hash (key doesn't exist)
      # 3. Otherwise instantiates object with returned data
      # - Best for: Bulk operations, performance-critical paths, when keys likely exist
      # - Commands: 1 per object (HGETALL only)
      # - Reduction: 50% fewer Redis commands
      #
      # @example Safe mode (default)
      #   User.find_by_key("user:123")  # 2 commands: EXISTS + HGETALL
      #
      # @example Optimized mode (skip existence check)
      #   User.find_by_key("user:123", check_exists: false)  # 1 command: HGETALL
      #
      # @note When check_exists: false, HGETALL on non-existent keys returns {}
      #   which we detect and return nil (not an empty object instance).
      #
      def find_by_dbkey(objkey, check_exists: true)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        if check_exists
          # Safe mode: Check existence first (original behavior)
          # We use a lower-level method here b/c we're working with the
          # full key and not just the identifier.
          does_exist = dbclient.exists(objkey).positive?

          Familia.debug "[find_by_key] #{self} from key #{objkey} (exists: #{does_exist})"
          Familia.trace :FIND_BY_DBKEY_KEY, nil, objkey

          # This is the reason for calling exists first. We want to definitively
          # and without any ambiguity know if the object exists in the database. If it
          # doesn't, we return nil. If it does, we proceed to load the object.
          # Otherwise, hgetall will return an empty hash, which will be passed to
          # the constructor, which will then be annoying to debug.
          return unless does_exist
        else
          # Optimized mode: Skip existence check
          Familia.debug "[find_by_key] #{self} from key #{objkey} (check_exists: false)"
          Familia.trace :FIND_BY_DBKEY_KEY, nil, objkey
        end

        obj = dbclient.hgetall(objkey) # horreum objects are persisted as database hashes
        Familia.trace :FIND_BY_DBKEY_INSPECT, nil, "#{objkey}: #{obj.inspect}"

        # If we skipped existence check and got empty hash, key doesn't exist
        return nil if !check_exists && obj.empty?

        # Create instance and deserialize fields using shared helper method
        instantiate_from_hash(obj)
      end
      alias find_by_key find_by_dbkey

      # Retrieves and instantiates an object from Database using its identifier.
      #
      # @param identifier [String, Integer] The unique identifier for the
      #   object.
      # @param suffix [Symbol, nil] The suffix to use in the dbkey (default:
      #   class suffix). Keyword parameter for consistency with check_exists.
      # @param check_exists [Boolean] Whether to check key existence before HGETALL
      #   (default: true). See find_by_dbkey for details.
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
      # @example Safe mode (default)
      #   User.find_by_id(123)  # 2 commands: EXISTS + HGETALL
      #
      # @example Optimized mode
      #   User.find_by_id(123, check_exists: false)  # 1 command: HGETALL
      #
      # @example Custom suffix
      #   Session.find_by_id('abc', suffix: :session)
      #
      def find_by_identifier(identifier, suffix: nil, check_exists: true)
        suffix ||= self.suffix
        return nil if identifier.to_s.empty?

        objkey = dbkey(identifier, suffix)

        Familia.debug "[find_by_id] #{self} from key #{objkey})"
        Familia.trace :FIND_BY_ID, nil, objkey if Familia.debug?
        find_by_dbkey objkey, check_exists: check_exists
      end
      alias find_by_id find_by_identifier
      alias find find_by_id
      alias load find_by_id

      # Loads multiple objects by their identifiers using pipelined HGETALL commands.
      #
      # This method provides significant performance improvements for bulk loading by:
      # 1. Batching all HGETALL commands into a single Redis pipeline
      # 2. Eliminating network round-trip overhead
      # 3. Skipping individual EXISTS checks (like check_exists: false)
      #
      # @param identifiers [Array<String, Integer>] Array of identifiers to load
      # @param suffix [Symbol, nil] The suffix to use in dbkeys (default: class suffix)
      # @return [Array<Object>] Array of instantiated objects (nils for non-existent)
      #
      # Performance characteristics:
      # - Standard approach: N objects × 2 commands (EXISTS + HGETALL) = 2N round trips
      # - check_exists: false: N objects × 1 command (HGETALL) = N round trips
      # - load_multi: 1 pipeline with N commands = 1 round trip
      # - Improvement: Up to 2N× faster for bulk operations
      #
      # @example Load multiple users efficiently
      #   users = User.load_multi([123, 456, 789])
      #   # 1 pipeline with 3 HGETALL commands instead of 6 individual commands
      #
      # @example Filter out nils
      #   existing_users = User.load_multi(ids).compact
      #
      # @note Returns nil for non-existent keys (maintains same contract as find_by_id)
      # @note Objects are returned in the same order as input identifiers
      # @note Empty/nil identifiers are skipped and return nil in result array
      #
      def load_multi(identifiers, suffix = nil)
        suffix ||= self.suffix
        return [] if identifiers.empty?

        # Build list of valid keys and track their original positions
        valid_keys = []
        valid_positions = []

        identifiers.each_with_index do |identifier, idx|
          next if identifier.to_s.empty?

          valid_keys << dbkey(identifier, suffix)
          valid_positions << idx
        end

        Familia.trace :LOAD_MULTI, nil, "Loading #{identifiers.size} objects" if Familia.debug?

        # Pipeline all HGETALL commands
        multi_result = pipelined do |pipeline|
          valid_keys.each do |objkey|
            pipeline.hgetall(objkey)
          end
        end

        # Extract results array from MultiResult
        results = multi_result.results

        # Map results back to original positions
        objects = Array.new(identifiers.size)
        valid_positions.each_with_index do |pos, result_idx|
          obj_hash = results[result_idx]

          # Skip empty hashes (non-existent keys)
          next if obj_hash.nil? || obj_hash.empty?

          # Instantiate object using shared helper method
          objects[pos] = instantiate_from_hash(obj_hash)
        end

        objects
      end
      alias load_batch load_multi

      # Loads multiple objects by their full dbkeys using pipelined HGETALL commands.
      #
      # This is a lower-level variant of load_multi that works directly with dbkeys
      # instead of identifiers. Useful when you already have the full keys.
      #
      # @param objkeys [Array<String>] Array of full dbkeys to load
      # @return [Array<Object>] Array of instantiated objects (nils for non-existent)
      #
      # @example Load objects by full keys
      #   keys = ["user:123:object", "user:456:object"]
      #   users = User.load_multi_by_keys(keys)
      #
      # @note Returns nil for empty/nil keys, maintaining position alignment with input array
      #
      # @see load_multi For loading by identifiers
      #
      def load_multi_by_keys(objkeys)
        return [] if objkeys.empty?

        Familia.trace :LOAD_MULTI_BY_KEYS, nil, "Loading #{objkeys.size} objects" if Familia.debug?

        # Track which positions have valid keys to maintain result array alignment
        valid_positions = []
        objkeys.each_with_index do |objkey, idx|
          valid_positions << idx unless objkey.to_s.empty?
        end

        # Pipeline all HGETALL commands for valid keys
        multi_result = pipelined do |pipeline|
          objkeys.each do |objkey|
            next if objkey.to_s.empty?

            pipeline.hgetall(objkey)
          end
        end

        # Extract results array from MultiResult
        results = multi_result.results

        # Map results back to original positions
        objects = Array.new(objkeys.size)
        valid_positions.each_with_index do |pos, result_idx|
          obj_hash = results[result_idx]

          # Skip empty hashes (non-existent keys)
          next if obj_hash.nil? || obj_hash.empty?

          # Instantiate object using shared helper method
          objects[pos] = instantiate_from_hash(obj_hash)
        end

        objects
      end

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
        raise Familia::NoIdentifier, "#{self} requires non-empty identifier" if identifier.to_s.empty?

        objkey = dbkey identifier, suffix

        # Execute all deletion operations within a transaction
        transaction do |conn|
          # Clean up related fields first to avoid orphaned keys
          if relations?
            Familia.trace :DESTROY_RELATIONS!, nil, "#{self} has relations: #{related_fields.keys}" if Familia.debug?

            # Create a temporary instance to access related fields.
            # Pass identifier in constructor so init() sees it and can set dependent fields.
            identifier_field_name = identifier_field
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
        find_keys(suffix).filter_map { |k| find_by_key(k) }
      end

      # Returns the number of tracked instances (fast, from instances sorted set).
      #
      # This method provides O(1) performance by querying the `instances` sorted set,
      # which is automatically maintained when objects are created/destroyed through
      # Familia. However, objects deleted outside Familia (e.g., direct Redis commands)
      # may leave stale entries.
      #
      # @return [Integer] Number of instances in the instances sorted set
      #
      # @example
      #   User.create(email: 'test@example.com')
      #   User.count  #=> 1
      #
      # @note For authoritative count, use {#scan_count} (production-safe) or {#keys_count} (blocking)
      # @see #scan_count Production-safe authoritative count via SCAN
      # @see #keys_count Blocking authoritative count via KEYS
      # @see #instances The underlying sorted set
      #
      def count
        instances.count
      end
      alias size count
      alias length count

      # Returns authoritative count using blocking KEYS command (production-dangerous).
      #
      # ⚠️ WARNING: This method uses the KEYS command which blocks Redis during execution.
      # It scans ALL keys in the database and should NEVER be used in production.
      #
      # @param filter [String] Key pattern to match (default: '*')
      # @return [Integer] Number of matching keys in Redis
      #
      # @example
      #   User.keys_count       #=> 1  (all User objects)
      #   User.keys_count('a*') #=> 1  (Users with IDs starting with 'a')
      #
      # @note For production-safe authoritative count, use {#scan_count}
      # @see #scan_count Production-safe alternative using SCAN
      # @see #count Fast count from instances sorted set
      #
      def keys_count(filter = '*')
        dbclient.keys(dbkey(filter)).compact.size
      end

      # Returns authoritative count using non-blocking SCAN command (production-safe).
      #
      # This method uses cursor-based SCAN iteration to count matching keys without
      # blocking Redis. Safe for production use as it processes keys in chunks.
      #
      # @param filter [String] Key pattern to match (default: '*')
      # @return [Integer] Number of matching keys in Redis
      #
      # @example
      #   User.scan_count       #=> 1  (all User objects)
      #   User.scan_count('a*') #=> 1  (Users with IDs starting with 'a')
      #
      # @note For fast count (potentially stale), use {#count}
      # @see #count Fast count from instances sorted set
      # @see #keys_count Blocking alternative (production-dangerous)
      #
      def scan_count(filter = '*')
        pattern = dbkey(filter)
        count = 0
        cursor = '0'

        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: 1000)
          count += keys.size
          break if cursor == '0'
        end

        count
      end
      alias count! scan_count

      # Checks if any tracked instances exist (fast, from instances sorted set).
      #
      # This method provides O(1) performance by querying the `instances` sorted set.
      # However, objects deleted outside Familia may leave stale entries.
      #
      # @return [Boolean] true if instances sorted set is non-empty
      #
      # @example
      #   User.create(email: 'test@example.com')
      #   User.any?  #=> true
      #
      # @note For authoritative check, use {#scan_any?} (production-safe) or {#keys_any?} (blocking)
      # @see #scan_any? Production-safe authoritative check via SCAN
      # @see #keys_any? Blocking authoritative check via KEYS
      # @see #count Fast count of instances
      #
      def any?
        count.positive?
      end

      # Checks if any objects exist using blocking KEYS command (production-dangerous).
      #
      # ⚠️ WARNING: This method uses the KEYS command which blocks Redis during execution.
      # It scans ALL keys in the database and should NEVER be used in production.
      #
      # @param filter [String] Key pattern to match (default: '*')
      # @return [Boolean] true if any matching keys exist in Redis
      #
      # @example
      #   User.keys_any?       #=> true  (any User objects)
      #   User.keys_any?('a*') #=> true  (Users with IDs starting with 'a')
      #
      # @note For production-safe authoritative check, use {#scan_any?}
      # @see #scan_any? Production-safe alternative using SCAN
      # @see #any? Fast existence check from instances sorted set
      #
      def keys_any?(filter = '*')
        keys_count(filter).positive?
      end

      # Checks if any objects exist using non-blocking SCAN command (production-safe).
      #
      # This method uses cursor-based SCAN iteration to check for matching keys without
      # blocking Redis. Safe for production use and returns early on first match.
      #
      # @param filter [String] Key pattern to match (default: '*')
      # @return [Boolean] true if any matching keys exist in Redis
      #
      # @example
      #   User.scan_any?       #=> true  (any User objects)
      #   User.scan_any?('a*') #=> true  (Users with IDs starting with 'a')
      #
      # @note For fast check (potentially stale), use {#any?}
      # @see #any? Fast existence check from instances sorted set
      # @see #keys_any? Blocking alternative (production-dangerous)
      #
      def scan_any?(filter = '*')
        pattern = dbkey(filter)
        cursor = '0'

        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: 100)
          return true unless keys.empty?
          break if cursor == '0'
        end

        false
      end
      alias any! scan_any?

      # Instantiates an object from a hash of field values.
      #
      # This is an internal helper method used by find_by_dbkey, load_multi, and
      # load_multi_by_keys to eliminate code duplication. Not intended for direct use.
      #
      # @param obj_hash [Hash] Hash of field names to serialized values from Redis
      # @return [Object] Instantiated object with deserialized fields
      #
      # @note This method:
      #   1. Allocates a new instance without calling initialize
      #   2. Initializes related DataType fields
      #   3. Deserializes and assigns field values from the hash
      #
      # @api private
      def instantiate_from_hash(obj_hash)
        instance = allocate
        instance.send(:initialize_relatives)
        instance.send(:initialize_with_keyword_args_deserialize_value, **obj_hash)
        instance
      end
    end
  end
end
