# rubocop:disable all

module Familia

  @delim = ':'
  @prefix = nil
  @suffix = :object
  @ttl = nil
  @db = nil

  module Settings

    attr_writer :delim, :suffix, :ttl, :db, :prefix

    def delim(val = nil)
      @delim = val if val
      @delim
    end

    def prefix(val = nil)
      @prefix = val if val
      @prefix
    end

    def suffix(val = nil)
      @suffix = val if val
      @suffix
    end

    # We define this do-nothing method because it reads better
    # than simply Familia.suffix in some contexts.
    def default_suffix
      suffix
    end

  end

end
