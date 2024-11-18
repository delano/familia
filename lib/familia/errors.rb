# frozen_string_literal: true

module Familia
  class Problem < RuntimeError; end
  class NoIdentifier < Problem; end
  class NonUniqueKey < Problem; end

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

  # Raised when attempting to refresh an object whose key doesn't exist in Redis
  class KeyNotFoundError < Problem
    attr_reader :key

    def initialize(key)
      @key = key
      super
    end

    def message
      "Key not found in Redis: #{key}"
    end
  end
end
