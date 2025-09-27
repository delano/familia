# lib/familia/settings.rb

# Familia
#
module Familia
  @delim = ':'.freeze
  @prefix = nil
  @suffix = :object
  @default_expiration = 0 # see update_expiration. Zero is skip. nil is an exception.
  @logical_database = nil
  @encryption_keys = nil
  @current_key_version = nil
  @encryption_personalization = 'FamilialMatters'.freeze

  # Familia::Settings
  #
  module Settings
    attr_writer :delim, :suffix, :default_expiration, :logical_database, :prefix, :encryption_keys,
                :current_key_version, :encryption_personalization

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
      Familia.trace :DB, nil, "#{@logical_database} #{v}", caller(1..1) if Familia.debug?
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

    # Personalization string for BLAKE2b key derivation in XChaCha20Poly1305.
    # This provides cryptographic domain separation, ensuring derived keys are
    # unique per application even with identical master keys and contexts.
    # Must be 16 bytes or less (automatically padded with null bytes).
    #
    # @example Familia.configure do |config|
    #     config.encryption_personalization = 'MyApp1.0'
    #   end
    #
    # @param val [String, nil] The personalization string, or nil to get current value
    # @return [String] Current personalization string
    def encryption_personalization(val = nil)
      if val
        raise ArgumentError, 'Personalization string cannot exceed 16 bytes' if val.bytesize > 16

        @encryption_personalization = val
      end
      @encryption_personalization
    end

    # Configure Familia settings
    #
    # @yield [Settings] self for block-based configuration
    # @return [Settings] self for method chaining
    #
    # @example Block-based configuration
    #   Familia.configure do |config|
    #     config.redis_uri = "redis://localhost:6379/1"
    #     config.ttl = 3600
    #   end
    #
    # @example Method chaining
    #   Familia.configure.redis_uri = "redis://localhost:6379/1"
    def configure
      yield self if block_given?
      self
    end
    alias config configure
  end
end
