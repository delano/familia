module Familia
  class Problem < RuntimeError; end
  class NoIdentifier < Problem; end
  class NonUniqueKey < Problem; end

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
end
