# lib/familia/data_type.rb

require_relative 'data_type/commands'
require_relative 'data_type/serialization'

# Familia
#
module Familia
  # DataType - Base class for Database data type wrappers
  #
  # This class provides common functionality for various Database data types
  # such as String, List, Set, SortedSet, and HashKey.
  #
  # @abstract Subclass and implement Database data type specific methods
  class DataType
    include Familia::Base
    extend Familia::Features

    using Familia::Refinements::TimeLiterals

    @registered_types = {}
    @valid_options = %i[class parent default_expiration default logical_database dbkey dbclient suffix prefix]
    @logical_database = nil

    feature :expiration
    feature :quantization

    class << self
      attr_reader :registered_types, :valid_options, :has_relations
      attr_accessor :parent
      attr_writer :logical_database, :uri
    end

    # DataType::ClassMethods
    #
    module ClassMethods
      # To be called inside every class that inherits DataType
      # +methname+ is the term used for the class and instance methods
      # that are created for the given +klass+ (e.g. set, list, etc)
      def register(klass, methname)
        Familia.trace :REGISTER, nil, "[#{self}] Registering #{klass} as #{methname.inspect}", caller(1..1) if Familia.debug?

        @registered_types[methname] = klass
      end

      def logical_database(val = nil)
        @logical_database = val unless val.nil?
        @logical_database || parent&.logical_database
      end

      def uri(val = nil)
        @uri = val unless val.nil?
        @uri || (parent ? parent.uri : Familia.uri)
      end

      def inherited(obj)
        Familia.trace :DATATYPE, nil, "#{obj} is my kinda type", caller(1..1) if Familia.debug?
        obj.logical_database = logical_database
        obj.default_expiration = default_expiration # method added via Features::Expiration
        obj.uri = uri
        obj.parent = self
        super
      end

      def valid_keys_only(opts)
        opts.slice(*DataType.valid_options)
      end

      def relations?
        @has_relations ||= false # rubocop:disable ThreadSafety/ClassInstanceVariable
      end
    end
    extend ClassMethods

    attr_reader :keystring, :opts
    attr_writer :dump_method, :load_method

    # +keystring+: If parent is set, this will be used as the suffix
    # for dbkey. Otherwise this becomes the value of the key.
    # If this is an Array, the elements will be joined.
    #
    # Options:
    #
    # :class => A class that responds to Familia.load_method and
    # Familia.dump_method. These will be used when loading and
    # saving data from/to the database to unmarshal/marshal the class.
    #
    # :parent => The Familia object that this datatype object belongs
    # to. This can be a class that includes Familia or an instance.
    #
    # :default_expiration => the time to live in seconds. When not nil, this will
    # set the default expiration for this dbkey whenever #save is called.
    # You can also call it explicitly via #update_expiration.
    #
    # :default => the default value (String-only)
    #
    # :logical_database => the logical database index to use (ignored if :dbclient is used).
    #
    # :dbclient => an instance of database client.
    #
    # :dbkey => a hardcoded key to use instead of the deriving the from
    # the name and parent (e.g. a derived key: customer:custid:secret_counter).
    #
    # :suffix => the suffix to use for the key (e.g. 'scores' in customer:custid:scores).
    # :prefix => the prefix to use for the key (e.g. 'customer' in customer:custid:scores).
    #
    # Connection precendence: uses the database connection of the parent or the
    # value of opts[:dbclient] or Familia.dbclient (in that order).
    def initialize(keystring, opts = {})
      @keystring = keystring
      @keystring = @keystring.join(Familia.delim) if @keystring.is_a?(Array)

      # Remove all keys from the opts that are not in the allowed list
      @opts = opts || {}
      @opts = DataType.valid_keys_only(@opts)

      # Apply the options to instance method setters of the same name
      @opts.each do |k, v|
        # Bewarde logging :parent instance here implicitly calls #to_s which for
        # some classes could include the identifier which could still be nil at
        # this point. This would result in a Familia::Problem being raised. So
        # to be on the safe-side here until we have a better understanding of
        # the issue, we'll just log the class name for each key-value pair.
        Familia.trace :SETTING, nil, " [setting] #{k} #{v.class}", caller(1..1) if Familia.debug?
        send(:"#{k}=", v) if respond_to? :"#{k}="
      end

      init if respond_to? :init
    end

    def dbclient
      return Fiber[:familia_transaction] if Fiber[:familia_transaction]
      return @dbclient if @dbclient

      parent? ? parent.dbclient : Familia.dbclient(opts[:logical_database])
    end

    # Produces the full dbkey for this object.
    #
    # @return [String] The full dbkey.
    #
    # This method determines the appropriate dbkey based on the context of the DataType object:
    #
    # 1. If a hardcoded key is set in the options, it returns that key.
    # 2. For instance-level DataType objects, it uses the parent instance's dbkey method.
    # 3. For class-level DataType objects, it uses the parent class's dbkey method.
    # 4. For standalone DataType objects, it uses the keystring as the full dbkey.
    #
    # For class-level DataType objects (parent_class? == true):
    # - The suffix is optional and used to differentiate between different types of objects.
    # - If no suffix is provided, the class's default suffix is used (via the self.suffix method).
    # - If a nil suffix is explicitly passed, it won't appear in the resulting dbkey.
    # - Passing nil as the suffix is how class-level DataType objects are created without
    #   the global default 'object' suffix.
    #
    # @example Instance-level DataType
    #   user_instance.some_datatype.dbkey  # => "user:123:some_datatype"
    #
    # @example Class-level DataType
    #   User.some_datatype.dbkey  # => "user:some_datatype"
    #
    # @example Standalone DataType
    #   DataType.new("mykey").dbkey  # => "mykey"
    #
    # @example Class-level DataType with explicit nil suffix
    #   User.dbkey("123", nil)  # => "user:123"
    #
    def dbkey
      # Return the hardcoded key if it's set. This is useful for
      # support legacy keys that aren't derived in the same way.
      return opts[:dbkey] if opts[:dbkey]

      if parent_instance?
        # This is an instance-level datatype object so the parent instance's
        # dbkey method is defined in Familia::Horreum::InstanceMethods.
        parent.dbkey(keystring)
      elsif parent_class?
        # This is a class-level datatype object so the parent class' dbkey
        # method is defined in Familia::Horreum::DefinitionMethods.
        parent.dbkey(keystring, nil)
      else
        # This is a standalone DataType object where it's keystring
        # is the full database key (dbkey).
        keystring
      end
    end

    def class?
      !@opts[:class].to_s.empty? && @opts[:class].is_a?(Familia)
    end

    def parent_instance?
      parent.is_a?(Familia::Horreum)
    end

    def parent_class?
      parent.is_a?(Class) && parent <= Familia::Horreum
    end

    def parent?
      parent_class? || parent_instance?
    end

    def parent
      @opts[:parent]
    end


    def logical_database
      @opts[:logical_database] || self.class.logical_database
    end

    def uri
      # If a specific URI is set in opts, use it
      return @opts[:uri] if @opts[:uri]

      # If parent has a DB set, create a URI with that DB
      if parent? && parent.respond_to?(:logical_database) && parent.logical_database
        base_uri = self.class.uri || Familia.uri
        if base_uri
          uri_with_db = base_uri.dup
          uri_with_db.db = parent.logical_database
          return uri_with_db
        end
      end

      # Otherwise fall back to class URI
      self.class.uri
    end

    def dump_method
      @dump_method || self.class.dump_method
    end

    def load_method
      @load_method || self.class.load_method
    end

    include Commands
    include Serialization
  end

  require_relative 'data_type/types/list'
  require_relative 'data_type/types/unsorted_set'
  require_relative 'data_type/types/sorted_set'
  require_relative 'data_type/types/hashkey'
  require_relative 'data_type/types/string'
end
