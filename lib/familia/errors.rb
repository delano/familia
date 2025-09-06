# lib/familia/errors.rb
#
module Familia
  class Problem < RuntimeError; end
  class NoIdentifier < Problem; end
  class NonUniqueKey < Problem; end

  class FieldTypeError < Problem; end
  class AutoloadError < Problem; end

  class HighRiskFactor < Problem
    attr_reader :value

    def initialize(value)
      @value = value
      super
    end

    def message
      "High risk factor for serialization bugs: #{value}<#{value.class}>"
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

  # Set Familia.connection_provider or use middleware to provide connections.
  class NoConnectionAvailable < Problem; end

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
