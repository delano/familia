# lib/familia/settings.rb
#
# frozen_string_literal: true

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
  @pipelined_mode = :warn

  # Schema validation configuration
  @schema_path = nil      # Directory containing schema files (String or Pathname)
  @schemas = {}           # Hash mapping class names to schema file paths
  @schema_validator = :json_schemer # Validator type (:json_schemer, :none, or custom)

  # Familia::Settings
  #
  module Settings
    attr_writer :delim, :suffix, :default_expiration, :logical_database, :prefix, :encryption_keys,
                :current_key_version, :encryption_personalization, :transaction_mode,
                :schema_path, :schemas, :schema_validator

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
      Familia.trace :DB, nil, "#{@logical_database} #{v}" if Familia.debug?
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

    # Controls transaction behavior when connection handlers don't support transactions
    #
    # @param val [Symbol, nil] The transaction mode or nil to get current value
    # @return [Symbol] Current transaction mode (:strict, :warn, :permissive)
    #
    # Available modes:
    # - :warn (default): Log warning and execute commands individually
    # - :strict: Raise OperationModeError when transaction unavailable
    # - :permissive: Silently execute commands individually
    #
    # @example Setting transaction mode
    #   Familia.configure do |config|
    #     config.transaction_mode = :warn
    #   end
    #
    def transaction_mode(val = nil)
      if val
        unless [:strict, :warn, :permissive].include?(val)
          raise ArgumentError, 'Transaction mode must be :strict, :warn, or :permissive'
        end
        @transaction_mode = val
      end
      @transaction_mode || :warn  # default to warn mode
    end

    # Controls pipeline behavior when connection handlers don't support pipelines
    #
    # @param val [Symbol, nil] The pipeline mode or nil to get current value
    # @return [Symbol] Current pipeline mode (:strict, :warn, :permissive)
    #
    # Available modes:
    # - :warn (default): Log warning and execute commands individually
    # - :strict: Raise OperationModeError when pipeline unavailable
    # - :permissive: Silently execute commands individually
    #
    # @example Setting pipeline mode
    #   Familia.configure do |config|
    #     config.pipelined_mode = :permissive
    #   end
    #
    def pipelined_mode(val = nil)
      if val
        unless [:strict, :warn, :permissive].include?(val)
          raise ArgumentError, 'Pipeline mode must be :strict, :warn, or :permissive'
        end
        @pipelined_mode = val
      end
      @pipelined_mode || :warn  # default to warn mode
    end

    def pipelined_mode=(val)
      unless [:strict, :warn, :permissive].include?(val)
        raise ArgumentError, 'Pipeline mode must be :strict, :warn, or :permissive'
      end
      @pipelined_mode = val
    end

    # Directory containing schema files for JSON Schema validation.
    # When set, schema files are discovered by convention using the
    # underscored class name (e.g., Customer -> customer.json).
    #
    # @param val [String, Pathname, nil] The schema directory path, or nil to get current value
    # @return [String, Pathname, nil] Current schema path
    #
    # @example Convention-based schema discovery
    #   Familia.configure do |config|
    #     config.schema_path = 'schemas/models'
    #   end
    #
    def schema_path(val = nil)
      @schema_path = val if val
      @schema_path
    end

    # Hash mapping class names to their schema file paths.
    # Takes precedence over convention-based discovery via schema_path.
    #
    # @param val [Hash, nil] A hash of class name => schema path mappings, or nil to get current
    # @return [Hash] Current schema mappings
    #
    # @example Explicit schema mapping
    #   Familia.configure do |config|
    #     config.schemas = {
    #       'Customer' => 'schemas/customer.json',
    #       'Session'  => 'schemas/session.json'
    #     }
    #   end
    #
    def schemas(val = nil)
      @schemas = val if val
      @schemas || {}
    end

    # Validator type for JSON Schema validation.
    #
    # @param val [Symbol, Object, nil] The validator type or instance, or nil to get current
    # @return [Symbol, Object] Current validator setting
    #
    # Available options:
    # - :json_schemer (default): Use the json_schemer gem for validation
    # - :none: Disable schema validation entirely
    # - Custom instance: Any object responding to #validate
    #
    # @example Disable validation
    #   Familia.configure do |config|
    #     config.schema_validator = :none
    #   end
    #
    def schema_validator(val = nil)
      @schema_validator = val if val
      @schema_validator || :json_schemer
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
