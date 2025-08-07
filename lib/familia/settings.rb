# lib/familia/settings.rb

module Familia

  @delim = ':'
  @prefix = nil
  @suffix = :object
  @default_expiration = 0 # see update_expiration. Zero is skip. nil is an exception.
  @logical_database = nil
  @encryption_keys = nil
  @current_key_version = nil

  module Settings

    attr_writer :delim, :suffix, :default_expiration, :logical_database, :prefix, :encryption_keys, :current_key_version

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

    def default_expiration(v = nil)
      @default_expiration = v unless v.nil?
      @default_expiration
    end

    def logical_database(v = nil)
      Familia.trace :DB, dbclient, "#{@logical_database} #{v}", caller(1..1) if Familia.debug?
      @logical_database = v unless v.nil?
      @logical_database
    end

    # We define this do-nothing method because it reads better
    # than simply Familia.suffix in some contexts.
    def default_suffix
      suffix
    end

    def encryption_keys(val = nil)
      @encryption_keys = val if val
      @encryption_keys
    end

    def current_key_version(val = nil)
      @current_key_version = val if val
      @current_key_version
    end

    def config
      self
    end

  end
end
