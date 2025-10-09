# lib/familia/errors.rb
#
module Familia
  # Base exception class for all Familia errors
  class Problem < RuntimeError; end
  class NoIdentifier < Problem; end
  class NonUniqueKey < Problem; end

  class FieldTypeError < Problem; end
  class AutoloadError < Problem; end
  # Base exception class for Redis/persistence-related errors
  class PersistenceError < Problem; end

  class SerializerError < Problem; end
  # Base exception class for Horreum models
  class HorreumError < Problem; end

  # Raised when attempting to start transactions or pipelines on connection types that don't support them
  class OperationModeError < Problem; end

  class NotDistinguishableError < Problem
    attr_reader :value

    def initialize(value)
      @value = value
      super
    end

    def message
      "Cannot represent #{value}<#{value.class}> as a string"
    end
  end

  class NotConnected < Problem
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
  class NoConnectionAvailable < Problem; end

  # Raised when a load method fails to find the requested object
  class NotFound < Problem; end

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
