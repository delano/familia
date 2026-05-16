# lib/familia/data_type.rb
#
# frozen_string_literal: true

require_relative 'data_type/class_methods'
require_relative 'data_type/settings'
require_relative 'data_type/connection'
require_relative 'data_type/database_commands'
require_relative 'data_type/serialization'

# Familia
#
module Familia
  # DataType - Base class for Database data type wrappers
  #
  # This class provides common functionality for various Database data types
  # such as String, JsonStringKey, List, UnsortedSet, SortedSet, and HashKey.
  #
  # == Write Method Transaction Safety Audit (2026-02-25)
  #
  # All write methods use dbclient which is transaction-aware: inside a
  # Horreum#transaction block, Fiber[:familia_transaction] routes commands
  # through the transaction connection. Outside a transaction, each write
  # is a standalone command followed by a separate EXPIRE (2 round trips,
  # no atomicity guarantee between them).
  #
  # Methods marked read-then-write are NOT atomic outside of transactions.
  #
  #   Type        | Method           | Redis Cmd      | update_exp | Read-then-write
  #   ------------|------------------|----------------|------------|----------------
  #   UnsortedSet | add              | SADD           | yes        | no
  #   UnsortedSet | remove_element   | SREM           | yes        | no
  #   UnsortedSet | pop              | SPOP           | yes        | no
  #   UnsortedSet | move             | SMOVE          | yes        | no
  #   SortedSet   | add              | ZADD           | yes        | no
  #   SortedSet   | remove_element   | ZREM           | yes        | no
  #   SortedSet   | increment        | ZINCRBY        | yes        | no
  #   SortedSet   | decrement        | ZINCRBY (neg)  | yes (via increment) | no
  #   SortedSet   | remrangebyrank   | ZREMRANGEBYRANK| yes        | no
  #   SortedSet   | remrangebyscore  | ZREMRANGEBYSCORE| yes       | no
  #   HashKey     | []=              | HSET           | yes        | no
  #   HashKey     | hsetnx           | HSETNX         | conditional| no
  #   HashKey     | remove_field     | HDEL           | yes        | no
  #   HashKey     | increment        | HINCRBY        | yes        | no
  #   HashKey     | decrement        | HINCRBY (neg)  | yes (via increment) | no
  #   HashKey     | update           | HMSET          | yes        | no
  #   ListKey     | push             | RPUSH(+LTRIM)  | yes        | no
  #   ListKey     | unshift          | LPUSH(+LTRIM)  | yes        | no
  #   ListKey     | pop              | RPOP           | yes        | no
  #   ListKey     | shift            | LPOP           | yes        | no
  #   ListKey     | remove_element   | LREM           | yes        | no
  #   StringKey   | value=           | SET            | yes        | no
  #   StringKey   | setnx            | SETNX          | yes        | no
  #   StringKey   | increment        | INCR           | yes        | no
  #   StringKey   | incrementby      | INCRBY         | yes        | no
  #   StringKey   | decrement        | DECR           | yes        | no
  #   StringKey   | decrementby      | DECRBY         | yes        | no
  #   StringKey   | append           | APPEND         | yes        | no
  #   StringKey   | setbit           | SETBIT         | yes        | no
  #   StringKey   | setrange         | SETRANGE       | yes        | no
  #   StringKey   | getset           | GETSET         | yes        | no
  #   StringKey   | del              | DEL            | no         | no
  #   Counter     | reset            | SET (via set)  | yes (via value=) | no
  #   Counter     | incr_if_lt       | EVAL (Lua)     | yes        | no (atomic Lua)
  #   Lock        | acquire          | SETNX(+EXPIRE) | yes (via setnx) | no
  #   Lock        | release          | EVAL (Lua)     | no (deletes key) | no (atomic Lua)
  #   Lock        | force_unlock!    | DEL            | no (deletes key) | no
  #
  # Notes:
  # - Counter#increment_if_less_than uses a Lua script (EVAL) for atomic
  #   threshold check + increment. Previously used GET then conditional
  #   INCRBY which was not atomic outside of a transaction.
  # - Lock#release uses a Lua script (EVAL) which IS atomic on the server.
  # - StringKey#del and Lock methods that delete the key do not call
  #   update_expiration because the key no longer exists.
  # - HashKey#hsetnx only calls update_expiration when the field was
  #   actually set (ret == 1), which is correct conditional behavior.
  #
  # @abstract Subclass and implement Database data type specific methods
  class DataType
    include Familia::Base
    include Enumerable
    extend ClassMethods
    extend Familia::Features

    using Familia::Refinements::TimeLiterals

    @registered_types = {}
    @valid_options = %i[class parent default_expiration no_expiration default logical_database dbkey dbclient suffix prefix reference].freeze
    @logical_database = nil

    feature :expiration
    feature :quantization

    class << self
      attr_reader :registered_types, :valid_options, :has_related_fields
    end

    # +keystring+: If parent is set, this will be used as the suffix
    # for dbkey. Otherwise this becomes the value of the key.
    # If this is an Array, the elements will be joined.
    #
    # Options:
    #
    # :class => A class that responds to from_json. This will be used
    # when loading data from the database to unmarshal the class.
    # JSON serialization is used for all data storage.
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
      @opts = DataType.valid_keys_only(opts || {})

      # Apply the options to instance method setters of the same name
      @opts.each do |k, v|
        send(:"#{k}=", v) if respond_to? :"#{k}="
      end

      init if respond_to? :init
    end

    # Checks if the parent Horreum object has unsaved scalar field changes
    # and emits a warning (or raises) before a collection write.
    #
    # This guards against a subtle issue where collection operations (SADD,
    # RPUSH, ZADD, HSET) write to Redis immediately while scalar field
    # changes remain only in memory. If the process crashes before the
    # scalar fields are saved, the collection data is persisted but the
    # scalar data is lost, creating an inconsistent state.
    #
    # @return [void]
    # @raise [Familia::Problem] if Familia.strict_write_order is true
    #
    def warn_if_dirty!
      # Suppress warnings while parent is inside atomic_write — scalar setters in the block
      # make the object dirty by design, so firing warnings for each collection call is noise.
      return if @parent_ref.respond_to?(:atomic_write_mode?) && @parent_ref.atomic_write_mode?

      return unless @parent_ref.respond_to?(:dirty?) && @parent_ref.dirty?

      dirty = @parent_ref.dirty_fields
      message = "Writing to #{self.class.name} #{dbkey} while parent " \
                "#{@parent_ref.class.name} has unsaved scalar fields: #{dirty.join(', ')}"

      if Familia.strict_write_order
        raise Familia::Problem, message
      else
        Familia.warn message
      end
    end

    # Override the default_expiration instance method to inherit from the
    # parent Horreum when this DataType doesn't have its own explicit
    # default_expiration option. This enables TTL cascade: when a Horreum
    # class has `default_expiration 1.hour` and a relation like `set :tags`
    # doesn't specify its own, the tags set will use the parent's TTL.
    #
    # Precedence:
    # 1. Instance-level @default_expiration (set directly)
    # 2. Explicit opts[:default_expiration] (from relation declaration)
    # 3. Parent Horreum's default_expiration (cascade)
    # 4. Class-level default (Familia.default_expiration, typically 0)
    #
    # Relations with `no_expiration: true` are excluded from cascade and
    # always return 0 (no TTL).
    #
    # @return [Numeric] The expiration in seconds
    #
    def default_expiration
      return 0 if @opts && @opts[:no_expiration]

      # Check instance-level override first
      return @default_expiration if @default_expiration

      # Check explicit opts from relation declaration
      return @opts[:default_expiration] if @opts && @opts[:default_expiration]

      # Inherit from parent Horreum if available
      if @parent_ref.respond_to?(:default_expiration)
        parent_exp = @parent_ref.default_expiration
        return parent_exp if parent_exp && parent_exp > 0
      end

      # Fall back to class-level default
      self.class.default_expiration
    end

    # Iterates over identifiers, loading each as a Horreum record.
    #
    # This method is designed for DataTypes that store object identifiers
    # (typically with `reference: true`). It loads records in batches using
    # the parent class's `load_multi` method and yields each loaded record.
    #
    # Ghost identifiers (where the underlying key has expired) are silently
    # filtered out.
    #
    # @param batch_size [Integer] Number of identifiers to load per batch
    # @param write_size [Integer, nil] Controls pipelining depth for writes
    #   in the block. When nil, writes are serial. When set, fast writers
    #   in the block will be pipelined in groups of this size.
    # @param filters [Hash] Additional filter parameters passed to `each`
    #   (e.g., `since:`, `until:` for SortedSet, `matching:` for others)
    # @yield [record] Each loaded Horreum record (non-nil)
    # @return [Enumerator, self] Returns Enumerator if no block given, self otherwise
    #
    # @example Iterate over all records
    #   User.instances.each_record { |user| user.deactivate! }
    #
    # @example With time filter (for SortedSet)
    #   User.instances.each_record(since: 1.day.ago) { |u| notify(u) }
    #
    # @example Pipeline writes in groups
    #   items.each_record(batch_size: 500, write_size: 50) { |r| r.foo! 'bar' }
    #
    # @example Serial writes (no pipelining)
    #   items.each_record(write_size: nil) { |r| r.save }
    #
    def each_record(batch_size: 100, write_size: batch_size, **filters, &block)
      return to_enum(:each_record, batch_size: batch_size, write_size: write_size, **filters) unless block

      # Determine the class to load records from
      # For reference DataTypes, @opts[:class] holds the Horreum class
      record_class = @opts[:class]
      unless record_class&.respond_to?(:load_multi)
        raise Familia::Problem, "each_record requires a reference DataType with a :class option that responds to load_multi"
      end

      # Collect identifiers in batches
      buffer = []

      process_batch = lambda do |ids|
        return if ids.empty?

        # Load records using the class's load_multi (pipelined HGETALLs)
        records = record_class.load_multi(ids)

        # Filter out ghosts (nil results from expired keys)
        records.compact.each do |record|
          if write_size.nil?
            # Serial mode - no pipelining
            block.call(record)
          elsif write_size.positive?
            # Pipelined mode - use parent's pipeline infrastructure
            # The block is expected to use fast writers which will route
            # through the fiber-local pipeline handler
            block.call(record)
          else
            block.call(record)
          end
        end
      end

      # Iterate using the type's each method with any filters
      each(**filters) do |member|
        # Extract identifier from member (handles both raw IDs and scored tuples)
        identifier = member.is_a?(Array) ? member.first : member
        buffer << identifier

        if buffer.size >= batch_size
          process_batch.call(buffer)
          buffer.clear
        end
      end

      # Process remaining items
      process_batch.call(buffer) unless buffer.empty?

      self
    end

    include Settings
    include Connection
    include DatabaseCommands
    include Serialization
  end

  require_relative 'data_type/types/listkey'
  require_relative 'data_type/types/unsorted_set'
  require_relative 'data_type/types/sorted_set'
  require_relative 'data_type/types/hashkey'
  require_relative 'data_type/types/stringkey'
  require_relative 'data_type/types/json_stringkey'
end
