# lib/familia/data_type.rb
#
# frozen_string_literal: true

require_relative 'data_type/class_methods'
require_relative 'data_type/settings'
require_relative 'data_type/connection'
require_relative 'data_type/database_commands'
require_relative 'data_type/serialization'
require_relative 'data_type/scalar_base'
require_relative 'data_type/collection_base'

# Familia
#
module Familia
  # DataType - Base class for Database data type wrappers
  #
  # This class provides common functionality for various Database data types
  # such as String, JsonStringKey, List, UnsortedSet, SortedSet, and HashKey.
  #
  # == Mental Model: Live Proxies, Not Cached Relations
  #
  # Unlike ActiveRecord relations which return new objects that can cache
  # loaded records, DataType instances are:
  #
  # - **Memoized**: Same object on every access (stable object_id)
  # - **Uncached**: Every read method hits Redis — no local data cache
  # - **Frozen**: Class-level DataTypes are frozen for thread safety
  #
  # This means `define_singleton_method` raises FrozenError on class-level
  # DataTypes. To stub in tests, stub the class method returning the DataType.
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
    extend ClassMethods
    extend Familia::Features

    using Familia::Refinements::TimeLiterals

    @registered_types = {}
    @valid_options = %i[class parent default_expiration no_expiration default logical_database dbkey dbclient suffix prefix reference].freeze
    @logical_database = nil

    # Remediation hint appended to every dirty-write warning/raise message so
    # the fix is self-evident without a round trip back to the docs.
    DIRTY_WRITE_HINT = '(call #save first or wrap in atomic_write)'

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
    # Two flavours of this hazard are distinguished:
    #
    # 1. **New, unsaved parent** — the parent has never been persisted, so no
    #    hash key exists in Redis yet. This is the worst case: the collection
    #    write creates a key while *none* of the scalar data exists, leaving an
    #    orphaned collection with no parent hash if the process never saves.
    # 2. **Dirty after save** — the parent was persisted before and merely has
    #    uncommitted scalar changes. The parent hash already exists, so the
    #    inconsistency is a partial update rather than a fully orphaned record.
    #
    # The behavior splits into a raise path and a warning path:
    #
    # * Raise (exempt from dedup): when Familia.strict_write_order is true, when
    #   the resolved class mode is :strict, or when the parent is new & unsaved
    #   and Familia.raise_on_unsaved_parent_write is true (the default). The
    #   new-object case gets a distinct, stronger message because orphaning a
    #   record is rarely intended.
    # * Warn: otherwise the resolved dirty_write_warnings mode governs emission
    #   (see #resolve_dirty_warning_mode) -- :once (default) warns once per
    #   distinct dirty-field signature within a dirty window (deduped via the
    #   parent's #record_dirty_warning!), :warn warns on every collection write,
    #   and :off suppresses entirely.
    #
    # An active +atomic_write+ block suppresses everything, taking priority over
    # all of the above. Every message ends with the DIRTY_WRITE_HINT remediation.
    #
    # @return [void]
    # @raise [Familia::Problem] when Familia.strict_write_order is true, when the
    #   resolved mode is :strict, or when the parent is a new, unsaved object and
    #   Familia.raise_on_unsaved_parent_write is true (the default)
    #
    def warn_if_dirty!
      # Suppress warnings while parent is inside atomic_write — scalar setters in the block
      # make the object dirty by design, so firing warnings for each collection call is noise.
      return if @parent_ref.respond_to?(:atomic_write_mode?) && @parent_ref.atomic_write_mode?

      return unless @parent_ref.respond_to?(:dirty?) && @parent_ref.dirty?

      mode = resolve_dirty_warning_mode
      # "Off means off": an explicit :off opts the class out of dirty-write
      # diagnostics entirely -- no warning AND no raise. The class-level mode is
      # the most specific signal, so it overrides both global raise switches
      # (strict_write_order and raise_on_unsaved_parent_write), mirroring how a
      # local "ignore" beats a global warnings-as-errors escalation elsewhere.
      return if mode == :off

      new_record = parent_new_record?
      dirty      = @parent_ref.dirty_fields
      message    = dirty_write_message(new_record, dirty)

      raise Familia::Problem, message if raise_on_dirty_write?(mode, new_record)

      emit_dirty_warning(mode, message, dirty)
    end

    # Resolves the dirty-write warning mode for this DataType's parent.
    #
    # Reads the parent Horreum class's +dirty_write_warnings+ setting (which
    # itself walks the subclass chain and falls back to the
    # +Familia.dirty_write_warnings+ global). Older parents that predate the
    # class setting fall back to the global directly.
    #
    # @return [Symbol] one of :strict, :warn, :once, :off
    #
    def resolve_dirty_warning_mode
      parent_class = @parent_ref.class
      if parent_class.respond_to?(:dirty_write_warnings)
        parent_class.dirty_write_warnings
      else
        Familia.dirty_write_warnings
      end
    end

    # Whether a dirty collection write should raise instead of warn. Raise paths
    # take priority over the warning mode and are exempt from dedup:
    #   - strict_write_order raises every dirty write
    #   - the class opted into :strict
    #   - the parent is new & unsaved and raise_on_unsaved_parent_write is on
    #     (the #278 safety net: orphaning a collection is almost never intended)
    #
    # @return [Boolean]
    #
    def raise_on_dirty_write?(mode, new_record)
      Familia.strict_write_order || mode == :strict ||
        (new_record && Familia.raise_on_unsaved_parent_write)
    end

    # Builds the dirty-write message. A new, unsaved parent gets a distinct,
    # stronger message (the orphaned-data hazard); both variants end with the
    # DIRTY_WRITE_HINT remediation.
    #
    # @return [String]
    #
    def dirty_write_message(new_record, dirty)
      fields = dirty.join(', ')
      if new_record
        "Writing to #{self.class.name} #{dbkey} while parent " \
          "#{@parent_ref.class.name} is a new, unsaved object (no hash key " \
          "exists yet) with unsaved scalar fields: #{fields}. Save the parent " \
          "before mutating its collections to avoid orphaned data. #{DIRTY_WRITE_HINT}"
      else
        "Writing to #{self.class.name} #{dbkey} while parent " \
          "#{@parent_ref.class.name} has unsaved scalar fields: #{fields} #{DIRTY_WRITE_HINT}"
      end
    end

    # Emits the dirty-write warning for a non-raising mode. :warn warns on every
    # call; :once dedupes per distinct dirty signature within the window via the
    # parent's #record_dirty_warning!. (:off is handled upstream in #warn_if_dirty!.)
    #
    # @return [void]
    #
    def emit_dirty_warning(mode, message, dirty)
      return Familia.warn(message) if mode == :warn

      # :once (default) -- warn once per distinct dirty-field signature per window
      signature  = dirty.sort.freeze
      first_time = !@parent_ref.respond_to?(:record_dirty_warning!) ||
                   @parent_ref.record_dirty_warning!(signature)
      Familia.warn message if first_time
    end

    private :resolve_dirty_warning_mode, :raise_on_dirty_write?,
            :dirty_write_message, :emit_dirty_warning

    # Best-effort detection of whether the parent Horreum instance has never
    # been persisted — i.e. its hash key does not exist in Redis yet. This is
    # the most dangerous dirty-write scenario surfaced by #warn_if_dirty!:
    # mutating a collection now writes a Redis key while *none* of the parent's
    # scalar data exists, so a crash before #save orphans the collection with
    # no parent hash to anchor it.
    #
    # Only consulted from #warn_if_dirty!, which already guarantees @parent_ref
    # is a dirty Horreum instance. Conservative by design — returns false
    # (treat as "already persisted", the milder warning) whenever the state
    # cannot be cheaply and safely determined:
    #
    # * inside a transaction/pipeline, where an EXISTS probe would be queued
    #   into the caller's MULTI/EXEC and return a Redis::Future rather than a
    #   boolean;
    # * when the parent cannot answer #exists? (e.g. it has no identifier yet),
    #   which raises a Familia::Problem during the probe.
    #
    # @return [Boolean] true only when we can positively confirm the parent has
    #   no hash key in the database.
    #
    def parent_new_record?
      return false if Fiber[:familia_transaction] || Fiber[:familia_pipeline]
      return false unless @parent_ref.respond_to?(:exists?)

      !@parent_ref.exists?(check_size: false)
    rescue Familia::Problem => e
      # Could not determine the parent's persistence state (e.g. it has no
      # identifier yet); fall back to the milder "dirty after save" warning.
      # Surface the swallowed problem under debug only, so production pays just
      # one cheap boolean check (Familia.debug?) while real issues stay visible.
      Familia.trace :NEW_RECORD_PROBE, nil, @parent_ref.class, "#{e.class}: #{e.message}" if Familia.debug?
      false
    end
    private :parent_new_record?

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
