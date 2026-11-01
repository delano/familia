# lib/familia/errors.rb
#
# frozen_string_literal: true

module Familia
  # Base exception class for all Familia errors
  class Problem < RuntimeError; end

  # Base exception class for Redis/persistence-related errors
  class PersistenceError < Problem; end

  # Base exception class for Horreum models
  class HorreumError < Problem; end

  # Raised when an object creation fails (e.g. the identifier
  # is already in use)
  class CreationError < HorreumError; end

  # Raised when an object lacks a required identifier
  class NoIdentifier < HorreumError; end

  # Raised when a key is expected to be unique but isn't
  class NonUniqueKey < PersistenceError; end

  # Raised when watch failed (e.g. key was modified), typically
  # retry
  class OptimisticLockError < PersistenceError; end

  # Raised when a rebuild of a key is attempted while another rebuild holds
  # the advisory lock for it. Rebuilds fail fast: they never wait or retry,
  # because a second concurrent rebuild can only duplicate work and risk
  # swapping a stale snapshot over a newer one.
  class RebuildInProgressError < PersistenceError
    attr_reader :key

    def initialize(key)
      @key = key
      super("Rebuild already in progress for #{key}")
    end
  end

  # Raised when a rebuild discovers it no longer owns its advisory lock --
  # it stalled past the lock TTL and another rebuild took over. The stalled
  # rebuild aborts (dropping its temp key) rather than swapping its now-stale
  # snapshot over the successor's newer index. A subclass of
  # RebuildInProgressError because the cause is the same condition seen from
  # the other side: someone else is rebuilding this key.
  class RebuildLockLostError < RebuildInProgressError
    def message
      "Rebuild lock lost for #{key}: another rebuild took over"
    end
  end

  # Raised by Horreum#refresh! when the stored values it assigns would give
  # the object an identifier other than the one that named the key it read.
  # Examples are a stored identifier field that differs from the key, and
  # a stored hash that lacks a field a Proc or method identifier reads.
  # refresh! leaves the object as it was before raising, so it keeps the
  # key it had.
  #
  # +key+ is the key refresh! read. +resolved_key+ is the key the assigned
  # values resolve to, or nil when they give no identifier.
  class IdentifierMismatchError < HorreumError
    attr_reader :key, :resolved_key

    def initialize(key, resolved_key = nil)
      @key = key
      @resolved_key = resolved_key
      super(build_message)
    end

    private

    def build_message
      if resolved_key.nil?
        "Stored values at #{key} give no identifier"
      else
        "Stored values at #{key} name a different key: #{resolved_key}"
      end
    end
  end

  # Raised by the rebuild of a multi_index when a key it must write as a
  # bucket set cannot be used as one. The rebuild checks those keys before
  # it deletes or writes anything.
  #
  # A key conflicts when it holds a type other than set, such as the list
  # of a record whose identifier makes its keys share the bucket prefix.
  # It also conflicts when it holds a set that belongs to another existing
  # record of the same class with a longer identifier, such as the set
  # field of a record whose identifier equals a class-level index name
  # when a field value equals that field's name.
  #
  # A key also conflicts when the rebuild cannot tell whether it belongs
  # to another record: when it has more candidate owner records than
  # Familia::Features::Relationships::Indexing::RecordKeyOwnership::MAX_CANDIDATE_SPLITS,
  # as a field value that repeats the delimiter and an index name can
  # make it. This applies to the keys the rebuild writes and to the stale
  # buckets it would delete.
  #
  # +conflicts+ maps each such key to the type it holds, or to
  # RecordKeyOwnership::TOO_MANY_CANDIDATES (+:too_many_candidate_owners+)
  # when its owner was not checked. +owners+ maps each conflicting key
  # that is another record's key to that record's hash key.
  #
  # Such a key may be another record's data, so the rebuild does not
  # replace it. Inspect each key in +conflicts+. The rebuild can run once
  # none of them holds another type or belongs to another record, and
  # none has too many candidate owners.
  class IndexBucketConflictError < PersistenceError
    attr_reader :conflicts, :owners

    def initialize(conflicts, owners = {})
      @conflicts = conflicts
      @owners = owners
      listed = conflicts.map do |key, type|
        "#{key.inspect} (#{conflict_detail(type, owners[key])})"
      end
      message = "Multi-index bucket keys cannot be written as bucket sets: #{listed.join(', ')}. " \
                'The rebuild stopped before it deleted or wrote anything. ' \
                'It can run once none of these keys holds a type other than set or belongs to another record.'
      if conflicts.values.any?(Symbol)
        message += ' A key whose owner was not checked has more candidate owner records than the rebuild checks.'
      end
      super(message)
    end

    private

    def conflict_detail(type, owner)
      return "owner not checked: #{type}" if type.is_a?(Symbol)
      return "#{type} of record #{owner.inspect}" if owner

      type
    end
  end

  # Raised when a field type is invalid or unexpected
  class FieldTypeError < HorreumError; end

  # Raised when autoloading fails
  class AutoloadError < HorreumError; end

  # Raised when serialization or deserialization fails
  class SerializerError < HorreumError; end

  # Raised when attempting to start transactions or pipelines on
  # connection types that don't support them
  class OperationModeError < PersistenceError; end

  # Raised when attempting to call a major method like save when
  # inside a transaction or pipeline
  class NestedTransactionError < OperationModeError; end

  # Raised when both pipeline and transaction contexts are active.
  # These contexts are mutually exclusive — restructure code to use one or the other.
  class ConflictingContextError < OperationModeError; end

  # Raised when atomic_write cannot include all DataType fields because
  # they span multiple Redis databases (MULTI/EXEC cannot cross databases).
  class CrossDatabaseError < OperationModeError
    attr_reader :field_name, :field_database, :horreum_database

    def initialize(field_name, field_database, horreum_database)
      @field_name = field_name
      @field_database = field_database
      @horreum_database = horreum_database
      super(build_message)
    end

    private

    def build_message
      "Cannot include field #{field_name} (logical_database: #{field_database}) in " \
      "atomic_write: parent Horreum uses logical_database #{horreum_database}. " \
      "MULTI/EXEC cannot span multiple databases."
    end
  end

  # Raised when attempting to reference a field that doesn't exist
  class UnknownFieldError < HorreumError; end

  # Raised when configure_related_field targets a definition that has already
  # been materialized: an instance of the model was created (instance-level
  # fields freeze as a group in initialize_relatives) or the class-level
  # collection was accessed (each class-level field freezes on its own first
  # access). Reconfiguring after that point would leave already-built
  # DataTypes on the old options, so the late write fails loudly instead.
  class RelatedFieldFrozenError < HorreumError; end

  # Raised when a value cannot be converted to a distinguishable
  # string representation
  class NotDistinguishableError < HorreumError
    attr_reader :value

    def initialize(value)
      @value = value
      super
    end

    def message
      "Cannot represent #{value}<#{value.class}> as a string"
    end
  end

  # Raised when no connection is available for a given URI
  class NotConnected < PersistenceError
    attr_reader :uri

    def initialize(uri)
      @uri = uri
      super
    end

    def message
      "No client for #{uri.serverid}"
    end
  end

  # UnsortedSet Familia.connection_provider or use middleware
  # to provide connections.
  class NoConnectionAvailable < PersistenceError; end

  # Raised when a load method fails to find the requested object
  class NotFound < PersistenceError; end

  # Raised when attempting to refresh an object whose key
  # doesn't exist in the database
  class KeyNotFoundError < NonUniqueKey
    attr_reader :key

    def initialize(key)
      @key = key
      super
    end

    def message
      "Key not found: #{key}"
    end
  end

  # Raised when a fast-write method is asked to write a field that backs a
  # class-level index and cannot run the index claim first, which the
  # fail-closed ordering in ADR-0002 requires.
  #
  # multi_field_fast_write raises it outside a transaction or pipeline,
  # since its single HMSET leaves no room for the claim: use
  # multi_field_update, save_fields or save there. A field! fast writer
  # raises it inside a transaction or pipeline, where the claim cannot run
  # and where multi_field_update, save_fields and save raise
  # Familia::OperationModeError too: call field! or one of those methods
  # before or after the block.
  class IndexedFieldFastWriteError < PersistenceError
    attr_reader :field, :index_name, :offenders, :inside_block

    # @param field [Symbol] the (first) offending field
    # @param index_name [Symbol] the index that field backs
    # @param offenders [Array<Array(Symbol, Symbol)>, nil] every
    #   (field, index_name) pair the caller found. The message names them
    #   all, so a batch write with several indexed fields is diagnosed in
    #   one pass instead of one retry per field. field/index_name stay the
    #   first pair for callers that predate the batch guard.
    # @param inside_block [Boolean] whether the write was refused inside a
    #   transaction or pipeline, which changes the remedy the message gives
    def initialize(field, index_name, offenders: nil, inside_block: false)
      @field = field
      @index_name = index_name
      @offenders = offenders || [[field, index_name]]
      @inside_block = inside_block
      super(build_message)
    end

    private

    def build_message
      described = offenders.map { |f, idx| "#{f} (backs #{idx})" }.join(', ')
      if inside_block
        "Cannot fast-write #{described} inside a transaction or pipeline: " \
          'the class-level index claim cannot run there (ADR-0002). Call the ' \
          'fast writer, multi_field_update or save before or after the block.'
      else
        "Cannot fast-write #{described}: a class-level index cannot be " \
          'maintained by a single HMSET (ADR-0002). Use multi_field_update ' \
          'or save so the index is claimed and updated with the hash write.'
      end
    end
  end

  # Raised when attempting to create an object that already
  # exists in the database
  class RecordExistsError < NonUniqueKey
    attr_reader :key, :existing_id

    def initialize(key, existing_id: nil)
      @existing_id = existing_id
      @key = key
      super(key)
    end

    def message
      msg = "Key already exists: #{key}"
      begin
        msg << " (existing_id=#{existing_id})" unless existing_id.nil?
      rescue StandardError
        # existing_id may not support nil?/to_s (e.g. a Redis::Future captured
        # inside a MULTI); a diagnostic message must never raise itself.
      end
      msg
    end
  end
end
