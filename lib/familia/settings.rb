# rubocop:disable all

module Familia

  @delim = ':'
  @prefix = nil
  @suffix = :object
  @ttl = 0 # see update_expiration. Zero is skip. nil is an exception.
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

    def ttl(v = nil)
      @ttl = v unless v.nil?
      @ttl
    end

    def db(v = nil)
      Familia.trace :DB, redis, "#{@db} #{v}", caller(1..1) if Familia.debug?
      @db = v unless v.nil?
      @db
    end

    # We define this do-nothing method because it reads better
    # than simply Familia.suffix in some contexts.
    def default_suffix
      suffix
    end

  end
end
