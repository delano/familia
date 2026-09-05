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
  # class-level index. Fast writers issue a single HMSET with no surrounding
  # claim, so they cannot maintain index consistency without violating the
  # fail-closed ordering in ADR-0002. Use multi_field_update, save_fields,
  # or save for indexed fields.
  class IndexedFieldFastWriteError < PersistenceError
    attr_reader :field, :index_name, :offenders

    # @param field [Symbol] the (first) offending field
    # @param index_name [Symbol] the index that field backs
    # @param offenders [Array<Array(Symbol, Symbol)>, nil] every
    #   (field, index_name) pair the caller found. The message names them
    #   all, so a batch write with several indexed fields is diagnosed in
    #   one pass instead of one retry per field. field/index_name stay the
    #   first pair for callers that predate the batch guard.
    def initialize(field, index_name, offenders: nil)
      @field = field
      @index_name = index_name
      @offenders = offenders || [[field, index_name]]
      super(build_message)
    end

    private

    def build_message
      described = offenders.map { |f, idx| "#{f} (backs #{idx})" }.join(', ')
      "Cannot fast-write #{described}: a class-level index cannot be " \
        'maintained by a single HMSET (ADR-0002). Use multi_field_update ' \
        'or save so the index is claimed and updated with the hash write.'
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
