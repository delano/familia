# lib/familia/horreum/class_methods.rb

require_relative 'related_fields_management'

module Familia
  class Horreum
    # Class-level instance variables
    # These are set up as nil initially and populated later
    @dbclient = nil # TODO
    @identifier_field = nil
    @default_expiration = nil
    @logical_database = nil
    @uri = nil
    @suffix = nil
    @prefix = nil
    @fields = nil # []
    @class_related_fields = nil # {}
    @related_fields = nil # {}
    @dump_method = nil
    @load_method = nil

    # ClassMethods: Provides class-level functionality for Horreum
    #
    # This module is extended into classes that include Familia::Horreum,
    # providing methods for Database operations and object management.
    #
    # Key features:
    # * Includes RelatedFieldsManagement for DataType field handling
    # * Defines methods for managing fields, identifiers, and dbkeys
    # * Provides utility methods for working with Database objects
    #
    module ClassMethods
      include Familia::Settings
      include Familia::Horreum::RelatedFieldsManagement

      # Sets or retrieves the unique identifier field for the class.
      #
      # This method defines or returns the field or method that contains the unique
      # identifier used to generate the dbkey for the object. If a value is provided,
      # it sets the identifier field; otherwise, it returns the current identifier field.
      #
      # @param [Object] val the field name or method to set as the identifier field (optional).
      # @return [Object] the current identifier field.
      #
      def identifier_field(val = nil)
        if val
          # Validate identifier field definition at class definition time
          case val
          when Symbol, String, Proc
            @identifier_field = val
          else
            raise Problem, <<~ERROR
              Invalid identifier field definition: #{val.inspect}.
              Use a field name (Symbol/String) or Proc.
            ERROR
          end
        end
        @identifier_field
      end

      # Defines a field for the class and creates accessor methods.
      #
      # This method defines a new field for the class, creating getter and setter
      # instance methods similar to `attr_accessor`. It also generates a fast
      # writer method for immediate persistence to Redis.
      #
      # @param [Symbol, String] name the name of the field to define.
      #
      def field(name)
        fields << name
        attr_accessor name

        # Every field gets a fast attribute method for immediately persisting
        fast_attribute! name
      end

      # Defines a fast attribute method with a bang (!) suffix for a given
      # attribute name. Fast attribute methods are used to immediately read or
      # write attribute values from/to Redis. Calling a fast attribute method
      # has no effect on any of the object's other attributes and does not
      # trigger a call to update the object's expiration time.
      #
      # The dynamically defined method performs the following:
      # - Acts as both a reader and a writer method.
      # - When called without arguments, retrieves the current value from Redis.
      # - When called with an argument, persists the value to Database immediately.
      # - Checks if the correct number of arguments is provided (zero or one).
      # - Converts the provided value to a format suitable for Database storage.
      # - Uses the existing accessor method to set the attribute value when
      #   writing.
      # - Persists the value to Database immediately using the hset command when
      #   writing.
      # - Includes custom error handling to raise an ArgumentError if the wrong
      #   number of arguments is given.
      # - Raises a custom error message if an exception occurs during the
      #   execution of the method.
      #
      # @param [Symbol, String] name the name of the attribute for which the
      #   fast method is defined.
      # @return [Object] the current value of the attribute when called without
      #   arguments.
      # @raise [ArgumentError] if more than one argument is provided.
      # @raise [RuntimeError] if an exception occurs during the execution of the
      #   method.
      #
      def fast_attribute!(name = nil)
        # Fast attribute accessor method for the '#{name}' attribute.
        # This method provides immediate read and write access to the attribute
        # in Redis.
        #
        # When called without arguments, it retrieves the current value of the
        # attribute from Redis.
        # When called with an argument, it immediately persists the new value to
        # Redis.
        #
        # @overload #{name}!
        #   Retrieves the current value of the attribute from Redis.
        #   @return [Object] the current value of the attribute.
        #
        # @overload #{name}!(value)
        #   Sets and immediately persists the new value of the attribute to
        #   Redis.
        #   @param value [Object] the new value to set for the attribute.
        #   @return [Object] the newly set value.
        #
        # @raise [ArgumentError] if more than one argument is provided.
        # @raise [RuntimeError] if an exception occurs during the execution of
        #   the method.
        #
        # @note This method bypasses any object-level caching and interacts
        #   directly with Redis. It does not trigger updates to other attributes
        #   or the object's expiration time.
        #
        # @example
        #
        #      def #{name}!(*args)
        #        # Method implementation
        #      end
        #
        define_method :"#{name}!" do |*args|
          # Check if the correct number of arguments is provided (exactly one).
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0 or 1)" if args.size > 1

          val = args.first

          # If no value is provided to this fast attribute method, make a call
          # to the db to return the current stored value of the hash field.
          return hget name if val.nil?

          begin
            # Trace the operation if debugging is enabled.
            Familia.trace :FAST_WRITER, dbclient, "#{name}: #{val.inspect}", caller(1..1) if Familia.debug?

            # Convert the provided value to a format suitable for Database storage.
            prepared = serialize_value(val)
            Familia.ld "[.fast_attribute!] #{name} val: #{val.class} prepared: #{prepared.class}"

            # Use the existing accessor method to set the attribute value.
            send :"#{name}=", val

            # Persist the value to Database immediately using the hset command.
            hset name, prepared
          rescue Familia::Problem => e
            # Raise a custom error message if an exception occurs during the execution of the method.
            raise "#{name}! method failed: #{e.message}", e.backtrace
          end
        end
      end

      # Returns the list of field names defined for the class in the order
      # that they were defined. i.e. `field :a; field :b; fields => [:a, :b]`.
      def fields
        @fields ||= []
        @fields
      end

      def class_related_fields
        @class_related_fields ||= {}
        @class_related_fields
      end

      def related_fields
        @related_fields ||= {}
        @related_fields
      end

      def has_relations?
        @has_relations ||= false
      end

      def logical_database(v = nil)
        Familia.trace :DB, Familia.dbclient, "#{@logical_database} #{v}", caller(1..1) if Familia.debug?
        @logical_database = v unless v.nil?
        @logical_database || parent&.logical_database
      end

      def all(suffix = nil)
        suffix ||= self.suffix
        # objects that could not be parsed will be nil
        keys(suffix).filter_map { |k| find_by_key(k) }
      end

      def any?(filter = '*')
        matching_keys_count(filter) > 0
      end

      # Returns the number of dbkeys matching the given filter pattern
      # @param filter [String] dbkey pattern to match (default: '*')
      # @return [Integer] Number of matching keys
      def matching_keys_count(filter = '*')
        dbclient.keys(dbkey(filter)).compact.size
      end
      alias size matching_keys_count # For backwards compatibility

      def suffix(a = nil, &blk)
        @suffix = a || blk if a || !blk.nil?
        @suffix || Familia.default_suffix
      end

      # Sets or retrieves the prefix for generating Redis keys.
      #
      # @param a [String, Symbol, nil] the prefix to set (optional).
      # @return [String, Symbol] the current prefix.
      #
      # The exception is only raised when both @prefix is nil/falsy AND name is nil,
      # which typically occurs with anonymous classes that haven't had their prefix
      # explicitly set.
      #
      def prefix(a = nil)
        @prefix = a if a
        @prefix || begin
          if name.nil?
            raise Problem, 'Cannot generate prefix for anonymous class. ' \
                           'Use `prefix` method to set explicitly.'
          end
          name.downcase.gsub('::', Familia.delim).to_sym
        end
      end

      # Creates and persists a new instance of the class.
      #
      # @param *args [Array] Variable number of positional arguments to be passed
      #   to the constructor.
      # @param **kwargs [Hash] Keyword arguments to be passed to the constructor.
      # @return [Object] The newly created and persisted instance.
      # @raise [Familia::Problem] If an instance with the same identifier already
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
      # identifier already exists. If it does, a Familia::Problem exception is
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
      #
      def create(*, **)
        fobj = new(*, **)
        raise Familia::Problem, "#{self} already exists: #{fobj.dbkey}" if fobj.exists?

        fobj.save
        fobj
      end

      def multiget(*ids)
        ids = rawmultiget(*ids)
        ids.filter_map { |json| from_json(json) }
      end

      def rawmultiget(*ids)
        ids.collect! { |objid| dbkey(objid) }
        return [] if ids.compact.empty?

        Familia.trace :MULTIGET, dbclient, "#{ids.size}: #{ids}", caller(1..1) if Familia.debug?
        dbclient.mget(*ids)
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
      # 1. It first checks if the key exists in Redis. This is crucial because:
      #    - It provides a definitive answer about the object's existence.
      #    - It prevents ambiguity that could arise from `hgetall` returning an
      #      empty hash for non-existent keys, which could lead to the creation
      #      of "empty" objects.
      #
      # 2. If the key exists, it retrieves the object's data and instantiates
      #    it.
      #
      # This approach ensures that we only attempt to instantiate objects that
      # actually exist in Redis, improving reliability and simplifying
      # debugging.
      #
      # @example
      #   User.find_by_key("user:123")  # Returns a User instance if it exists,
      #   nil otherwise
      #
      def find_by_key(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        # We use a lower-level method here b/c we're working with the
        # full key and not just the identifier.
        does_exist = dbclient.exists(objkey).positive?

        Familia.ld "[.find_by_key] #{self} from key #{objkey} (exists: #{does_exist})"
        Familia.trace :FROM_KEY, dbclient, objkey, caller(1..1) if Familia.debug?

        # This is the reason for calling exists first. We want to definitively
        # and without any ambiguity know if the object exists in Redis. If it
        # doesn't, we return nil. If it does, we proceed to load the object.
        # Otherwise, hgetall will return an empty hash, which will be passed to
        # the constructor, which will then be annoying to debug.
        return unless does_exist

        obj = dbclient.hgetall(objkey) # horreum objects are persisted as database hashes
        Familia.trace :FROM_KEY2, dbclient, "#{objkey}: #{obj.inspect}", caller(1..1) if Familia.debug?

        new(**obj)
      end
      alias from_dbkey find_by_key # deprecated

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
      def find_by_id(identifier, suffix = nil)
        suffix ||= self.suffix
        return nil if identifier.to_s.empty?

        objkey = dbkey(identifier, suffix)

        Familia.ld "[.find_by_id] #{self} from key #{objkey})"
        Familia.trace :FIND_BY_ID, Familia.dbclient(uri), objkey, caller(1..1).first if Familia.debug?
        find_by_key objkey
      end
      alias find find_by_id
      alias load find_by_id # deprecated
      alias from_identifier find_by_id # deprecated

      # Checks if an object with the given identifier exists in Redis.
      #
      # @param identifier [String, Integer] The unique identifier for the object.
      # @param suffix [Symbol, nil] The suffix to use in the dbkey (default: class suffix).
      # @return [Boolean] true if the object exists, false otherwise.
      #
      # This method constructs the full dbkey using the provided identifier and suffix,
      # then checks if the key exists in Redis.
      #
      # @example
      #   User.exists?(123)  # Returns true if user:123:object exists in Redis
      #
      def exists?(identifier, suffix = nil)
        suffix ||= self.suffix
        return false if identifier.to_s.empty?

        objkey = dbkey identifier, suffix

        ret = dbclient.exists objkey
        Familia.trace :EXISTS, dbclient, "#{objkey} #{ret.inspect}", caller(1..1) if Familia.debug?

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
      #   User.destroy!(123)  # Removes user:123:object from Redis
      #
      def destroy!(identifier, suffix = nil)
        suffix ||= self.suffix
        return false if identifier.to_s.empty?

        objkey = dbkey identifier, suffix

        ret = dbclient.del objkey
        Familia.trace :DESTROY!, dbclient, "#{objkey} #{ret.inspect}", caller(1..1) if Familia.debug?
        ret.positive?
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
      def dbkey(identifier, suffix = self.suffix)
        # Familia.ld "[.dbkey] #{identifier} for #{self} (suffix:#{suffix})"
        raise NoIdentifier, self if identifier.to_s.empty?

        identifier &&= identifier.to_s
        Familia.dbkey(prefix, identifier, suffix)
      end

      def dump_method
        @dump_method || :to_json # Familia.dump_method
      end

      def load_method
        @load_method || :from_json # Familia.load_method
      end
    end
  end
end
