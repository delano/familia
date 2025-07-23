# rubocop:disable all

module Familia

  @delim = ':'
  @prefix = nil
  @suffix = :object
  @ttl = 0 # see update_expiration. Zero is skip. nil is an exception.
  @db = nil

  # Connection pool settings
  @pool_size = 10
  @pool_timeout = 5
  @enable_connection_pool = true

  module Settings

    attr_writer :delim, :suffix, :ttl, :db, :prefix, :pool_size, :pool_timeout, :enable_connection_pool

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

    def pool_size(v = nil)
      @pool_size = v unless v.nil?
      @pool_size
    end

    def pool_timeout(v = nil)
      @pool_timeout = v unless v.nil?
      @pool_timeout
    end

    def enable_connection_pool(v = nil)
      @enable_connection_pool = v unless v.nil?
      @enable_connection_pool
    end

  end

end
