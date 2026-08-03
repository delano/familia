# lib/familia/field_type.rb
#
# frozen_string_literal: true

module Familia
  # Base class for all field types in Familia
  #
  # Field types encapsulate the behavior for different kinds of fields,
  # including how their getter/setter methods are defined and how values
  # are serialized/deserialized.
  #
  # @example Creating a custom field type
  #   class TimestampFieldType < Familia::FieldType
  #     def define_setter(klass)
  #       field_name = @name
  #       klass.define_method :"#{@method_name}=" do |value|
  #         timestamp = value.is_a?(Time) ? value.to_i : value
  #         instance_variable_set(:"@#{field_name}", timestamp)
  #       end
  #     end
  #
  #     def define_getter(klass)
  #       field_name = @name
  #       klass.define_method @method_name do
  #         timestamp = instance_variable_get(:"@#{field_name}")
  #         timestamp ? Time.at(timestamp) : nil
  #       end
  #     end
  #   end
  #
  class FieldType
    attr_reader :name, :options, :method_name, :fast_method_name, :on_conflict, :loggable

    using Familia::Refinements::TimeLiterals

    # Initialize a new field type
    #
    # @param name [Symbol] The field name
    # @param as [Symbol, String, false] The method name (defaults to field name)
    #   If false, no accessor methods are created
    # @param fast_method [Symbol, String, false] The fast method name
    #   (defaults to "#{name}!"). If false, no fast method is created
    # @param on_conflict [Symbol] Conflict resolution strategy when method
    #   already exists (:raise, :skip, :warn, :overwrite)
    # @param loggable [Boolean] Whether this field should be included in
    #   serialization and logging operations (default: true)
    # @param options [Hash] Additional options for the field type
    #
    def initialize(name, as: name, fast_method: :"#{name}!", on_conflict: :raise, loggable: true, **options)
      @name = name.to_sym
      @method_name = as == false ? nil : as.to_sym
      @fast_method_name = fast_method == false ? nil : fast_method&.to_sym

      # Validate fast method name format
      if @fast_method_name && !@fast_method_name.to_s.end_with?('!')
        raise ArgumentError, "Fast method name must end with '!' (got: #{@fast_method_name})"
      end

      @on_conflict = on_conflict
      @loggable = loggable
      @options = options
    end

    # Install this field type on a class
    #
    # This method defines all necessary methods on the target class
    # and registers the field type for later reference.
    #
    # @param klass [Class] The class to install this field type on
    #
    def install(klass)
      if @method_name
        # For skip strategy, check for any method conflicts first
        if @on_conflict == :skip
          has_getter_conflict = klass.method_defined?(@method_name) || klass.private_method_defined?(@method_name)
          has_setter_conflict = klass.method_defined?(:"#{@method_name}=") || klass.private_method_defined?(:"#{@method_name}=")

          # If either getter or setter conflicts, skip the whole field
          return if has_getter_conflict || has_setter_conflict
        end

        define_getter(klass)
        define_setter(klass)
      end

      define_fast_writer(klass) if @fast_method_name
    end

    # Define the getter method on the target class
    #
    # Subclasses can override this to customize getter behavior.
    # The default implementation creates a simple attr_reader equivalent.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_getter(klass)
      field_name = @name
      method_name = @method_name

      handle_method_conflict(klass, method_name) do
        klass.define_method method_name do
          instance_variable_get(:"@#{field_name}")
        end
      end
    end

    # Define the setter method on the target class
    #
    # Subclasses can override this to customize setter behavior.
    # The default implementation creates a simple attr_writer equivalent.
    #
    # @param klass [Class] The class to define the method on
    #
    # @note This setter only updates the in-memory instance variable. Call
    #   +save+, +commit_fields+, or use the fast_writer (+field_name!+) to
    #   persist to Redis.
    #
    def define_setter(klass)
      field_name = @name
      method_name = @method_name

      handle_method_conflict(klass, :"#{method_name}=") do
        klass.define_method :"#{method_name}=" do |value|
          old_value = instance_variable_get(:"@#{field_name}")
          instance_variable_set(:"@#{field_name}", value)

          # Track the change for dirty-tracking (only for Horreum instances)
          mark_dirty!(field_name, old_value) if respond_to?(:mark_dirty!)
        end
      end
    end

    # Define the fast writer method on the target class
    #
    # Fast methods provide direct database access for immediate persistence.
    # Subclasses can override this to customize fast method behavior.
    #
    # Fields backing a class-level index are maintained fail-closed (#308):
    # outside any transaction/pipeline the unique claim runs before the hash
    # write (a conflict raises Familia::RecordExistsError and the hash is
    # untouched); inside a caller's MULTI/pipeline no claim is possible, so
    # the writer raises Familia::IndexedFieldFastWriteError rather than write
    # the hash and leave the index stale. Non-indexed fields are unaffected.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_fast_writer(klass)
      return unless @fast_method_name&.to_s&.end_with?('!')

      field_name = @name
      fast_method_name = @fast_method_name
      field_type = self

      # Lives in the closure (not an ivar) because field types are frozen
      # after installation.
      index_rel_cache = {}.compare_by_identity

      handle_method_conflict(klass, fast_method_name) do
        klass.define_method fast_method_name do |*args|
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0 or 1)" if args.size > 1

          val = args.first

          # If no value provided, return current stored value
          # Handle Redis::Future objects during transactions
          return hget(field_name) if val.nil? || val.is_a?(Redis::Future)

          index_rels = field_type.send(:class_index_relationships, index_rel_cache, self.class)
          field_type.send(:guard_indexed_fast_write!, index_rels)

          # Trace the operation if debugging is enabled
          Familia.trace :FAST_WRITER, nil, "#{field_name}: #{val.inspect}" if Familia.debug?

          # Convert value for database storage
          prepared = serialize_value(val)
          Familia.debug "[FieldType#define_fast_writer] #{fast_method_name} val: #{val.class} prepared: #{prepared.class}"

          # Runs the setter, then claims and updates any class-level index
          # entries before the hash write below (ADR-0002 fail-closed
          # ordering). A claim conflict restores the in-memory state and
          # propagates typed, so the hash write never runs.
          field_type.send(:apply_fast_write_value, self, val, index_rels)

          begin
            # Persist to database immediately
            ret = hset(field_name, prepared)

            # Touch instances timeline so the object is visible
            # to list-based enumeration (instances.to_a, count, etc.)
            touch_instances! if respond_to?(:touch_instances!)

            clear_dirty!(field_name) if respond_to?(:clear_dirty!)

            Familia.success?(ret)
          rescue Familia::Problem => e
            raise "#{fast_method_name} method failed: #{e.message}", e.backtrace
          end
        end
      end
    end

    # Whether this field should be persisted to the database
    #
    # @return [Boolean] true if field should be persisted
    #
    def persistent?
      true
    end

    def transient?
      !persistent?
    end

    # The category for this field type (used for filtering)
    #
    # @return [Symbol] the field category
    #
    def category
      :field
    end

    # Serialize a value for database storage
    #
    # Subclasses can override this to customize serialization.
    # The default implementation passes values through unchanged.
    #
    # @param value [Object] The value to serialize
    # @param _record [Object] The record instance (for context)
    # @return [Object] The serialized value
    #
    def serialize(value, _record = nil)
      value
    end

    # Deserialize a value from database storage
    #
    # Subclasses can override this to customize deserialization.
    # The default implementation passes values through unchanged.
    #
    # @param value [Object] The value to deserialize
    # @param _record [Object] The record instance (for context)
    # @return [Object] The deserialized value
    #
    def deserialize(value, _record = nil)
      value
    end

    # Returns all method names generated for this field (used for conflict detection)
    #
    # @return [Array<Symbol>] Array of method names this field type generates
    #
    def generated_methods
      [@method_name, @fast_method_name].compact
    end

    # Enhanced inspection output for debugging
    #
    # @return [String] Human-readable representation
    #
    def inspect
      attributes = [
        "name=#{@name}",
        "method_name=#{@method_name}",
        "fast_method_name=#{@fast_method_name}",
        "on_conflict=#{@on_conflict}",
        "category=#{category}",
      ]
      "#<#{self.class.name} #{attributes.join(' ')}>"
    end
    alias to_s inspect

    private

    # The class-level indexing relationships backed by this field on
    # +record_class+ (unique_index and multi_index alike).
    #
    # Not resolvable at install time: unique_index/multi_index declarations
    # typically follow the field declaration in the class body. Memoized
    # lazily per runtime class (subclasses can add indexes on inherited
    # fields), so non-indexed fields pay one Hash lookup per call. The cache
    # is closure-owned by the generated method (field types are frozen after
    # installation) and identity-keyed: Horreum classes define a `hash` DSL
    # method (the related-field kind) that shadows Object#hash, so a regular
    # Hash lookup keyed by the class would invoke it with no args. Each entry
    # also records the class's relationship count at resolution time, so an
    # index declared AFTER the first fast write invalidates the memo instead
    # of being silently skipped.
    #
    # @param cache [Hash] identity-compared memo owned by the caller
    # @param record_class [Class] the runtime class of the record
    # @return [Array<IndexingRelationship>] frozen, possibly empty
    #
    def class_index_relationships(cache, record_class)
      count = if record_class.respond_to?(:indexing_relationships)
        record_class.indexing_relationships.size
      else
        0
      end

      cached_count, cached_rels = cache[record_class]
      return cached_rels if cached_rels && cached_count == count

      rels = resolve_class_index_relationships(record_class)
      cache[record_class] = [count, rels]
      rels
    end

    # Uncached resolution behind {#class_index_relationships}.
    #
    # @param record_class [Class]
    # @return [Array<IndexingRelationship>] frozen
    #
    def resolve_class_index_relationships(record_class)
      return [].freeze unless record_class.respond_to?(:indexing_relationships)

      record_class.indexing_relationships.select do |rel|
        rel.class_level? && rel.field == @name
      end.freeze
    end

    # Refuses an indexed fast write queued into a caller's MULTI/pipeline.
    # The unique claim (a Lua CAS EVAL) cannot run there -- its verdict would
    # be a Future -- so writing the hash would leave the index stale. See
    # ADR-0002 and #308.
    #
    # @param index_rels [Array<IndexingRelationship>]
    # @raise [Familia::IndexedFieldFastWriteError]
    # @return [void]
    #
    def guard_indexed_fast_write!(index_rels)
      return if index_rels.empty?
      return unless Fiber[:familia_transaction] || Fiber[:familia_pipeline]

      raise Familia::IndexedFieldFastWriteError.new(@name, index_rels.first.index_name)
    end

    # Applies the in-memory setter, then maintains the class-level index
    # entries for +index_rels+ before the caller's hash write: the dirty map
    # recorded by the setter supplies the old value to release, the getter
    # supplies the new value to claim (update_in_class_* self-claims outside
    # a transaction). On failure the record's in-memory state is restored
    # and the error propagates typed, so the hash write never happens.
    #
    # @param record [Familia::Horreum] the record being written
    # @param value [Object] the new field value
    # @param index_rels [Array<IndexingRelationship>]
    # @return [void]
    #
    def apply_fast_write_value(record, value, index_rels)
      if index_rels.empty?
        record.send(:"#{@method_name}=", value) if @method_name
        return
      end

      snapshot = record.send(:capture_field_rollback_state, [@name])
      record.send(:"#{@method_name}=", value) if @method_name

      begin
        changes = record.respond_to?(:changed_fields) ? record.changed_fields : {}
        index_rels.each { |rel| record.send(:apply_class_index_change, rel, changes) }
      rescue StandardError
        record.send(:restore_field_rollback_state, snapshot)
        raise
      end
    end

    # Handle method name conflicts during definition
    #
    # @param klass [Class] The target class
    # @param method_name [Symbol] The method name to define
    # @yield Block that defines the method
    #
    def handle_method_conflict(klass, method_name)
      case @on_conflict
      when :skip
        return if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
      when :warn
        if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
          warn <<~WARNING

            WARNING: Method >>> #{method_name} <<< already exists on #{klass}.
            Field functionality may be broken. Consider using a different name
            with field(:#{@name}, as: :other_name)

            Called from:
            #{Familia.pretty_stack(limit: 3)}

          WARNING
        end
      when :raise
        if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
          raise ArgumentError, "Method >>> #{method_name} <<< already defined for #{klass}"
        end
      when :overwrite
        # Proceed silently - allow overwrite
      else
        raise ArgumentError, "Unknown conflict resolution strategy: #{@on_conflict}"
      end

      yield
    end
  end
end
