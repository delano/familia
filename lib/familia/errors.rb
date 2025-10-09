# lib/familia/errors.rb
#
module Familia
  # Base exception class for all Familia errors
  class Problem < RuntimeError; end

  # Base exception class for Redis/persistence-related errors
  class PersistenceError < Problem; end

  # Base exception class for Horreum models
  class HorreumError < Problem; end

  # Raised when an object lacks a required identifier
  class NoIdentifier < HorreumError; end

  # Raised when a key is expected to be unique but isn't
  class NonUniqueKey < PersistenceError; end

  # Raised when a field type is invalid or unexpected
  class FieldTypeError < HorreumError; end

  # Raised when autoloading fails
  class AutoloadError < HorreumError; end

  # Raised when serialization or deserialization fails
  class SerializerError < HorreumError; end

  # Raised when attempting to start transactions or pipelines on connection types that don't support them
  class OperationModeError < PersistenceError; end

  # Raised when attempting to reference a field that doesn't exist
  class UnknownFieldError < HorreumError; end

  # Raised when a value cannot be converted to a distinguishable string representation
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

  # UnsortedSet Familia.connection_provider or use middleware to provide connections.
  class NoConnectionAvailable < PersistenceError; end

  # Raised when a load method fails to find the requested object
  class NotFound < PersistenceError; end

  # Raised when attempting to refresh an object whose key doesn't exist in the database
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

  # Raised when attempting to create an object that already exists in the database
  class RecordExistsError < NonUniqueKey
    attr_reader :key

    def initialize(key)
      @key = key
      super
    end

    def message
      "Key already exists: #{key}"
    end
  end
end
