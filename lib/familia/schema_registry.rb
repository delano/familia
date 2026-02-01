# lib/familia/schema_registry.rb
#
# frozen_string_literal: true

require 'json'

module Familia
  # Registry for loading and caching external JSON schema files.
  # Schemas are loaded at boot time based on configuration.
  #
  # @example Convention-based loading
  #   Familia.schema_path = 'schemas/models'
  #   SchemaRegistry.load!
  #   SchemaRegistry.schema_for('Customer')  # loads schemas/models/customer.json
  #
  # @example Explicit mapping
  #   Familia.schemas = { 'Customer' => 'schemas/customer.json' }
  #   SchemaRegistry.load!
  #
  class SchemaRegistry
    class << self
      # Load schemas based on current configuration.
      # Safe to call multiple times - only loads once.
      def load!
        return if @loaded

        @schemas ||= {}
        load_from_path if Familia.schema_path
        load_from_hash if Familia.schemas&.any?
        @loaded = true
      end

      # Check if schemas have been loaded
      def loaded?
        @loaded == true
      end

      # Get schema for a class by name or class reference
      # @param klass_or_name [Class, String] the class or class name
      # @return [Hash, nil] the parsed JSON schema or nil
      def schema_for(klass_or_name)
        load! unless loaded?
        name = klass_or_name.is_a?(Class) ? klass_or_name.name : klass_or_name.to_s
        @schemas[name]
      end

      # Check if a schema is defined for the given class
      def schema_defined?(klass_or_name)
        !schema_for(klass_or_name).nil?
      end

      # All registered schemas
      def schemas
        load! unless loaded?
        @schemas.dup
      end

      # Validate data against a schema
      # @param klass_or_name [Class, String] the class whose schema to use
      # @param data [Hash] the data to validate
      # @return [Hash] { valid: Boolean, errors: Array }
      def validate(klass_or_name, data)
        schema = schema_for(klass_or_name)
        return { valid: true, errors: [] } unless schema

        errors = validator.validate(schema, data).to_a
        { valid: errors.empty?, errors: errors }
      end

      # Validate data or raise SchemaValidationError
      # @raise [SchemaValidationError] if validation fails
      def validate!(klass_or_name, data)
        result = validate(klass_or_name, data)
        raise SchemaValidationError.new(result[:errors]) unless result[:valid]

        true
      end

      # Reset registry (primarily for testing)
      def reset!
        @schemas = {}
        @loaded = false
        @validator = nil
      end

      private

      def load_from_path
        path = Familia.schema_path
        return unless path && File.directory?(path)

        Dir.glob(File.join(path, '*.json')).each do |file|
          # Convert filename to class name: customer.json -> Customer
          # user_session.json -> UserSession
          basename = File.basename(file, '.json')
          class_name = basename.split('_').map(&:capitalize).join
          @schemas[class_name] = load_schema_file(file)
        end
      end

      def load_from_hash
        Familia.schemas.each do |class_name, file_path|
          @schemas[class_name.to_s] = load_schema_file(file_path)
        end
      end

      def load_schema_file(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        warn "Failed to parse schema file #{path}: #{e.message}"
        nil
      rescue Errno::ENOENT => e
        warn "Schema file not found: #{path}"
        nil
      end

      def validator
        @validator ||= build_validator
      end

      def build_validator
        case Familia.schema_validator
        when :json_schemer
          begin
            require 'json_schemer'
            JsonSchemerValidator.new
          rescue LoadError
            warn '[Familia] json_schemer gem not installed. Schema validation disabled.'
            warn "[Familia] Add `gem 'json_schemer'` to your Gemfile to enable."
            NullValidator.new
          end
        when :none, nil
          NullValidator.new
        else
          # Custom validator instance provided
          Familia.schema_validator
        end
      end
    end
  end

  # Validator adapter for json_schemer gem
  class JsonSchemerValidator
    def validate(schema, data)
      schemer = JSONSchemer.schema(schema)
      schemer.validate(data)
    end
  end

  # Null validator that always passes (for when validation is disabled)
  class NullValidator
    def validate(_schema, _data)
      []
    end
  end

  # Error raised when schema validation fails
  class SchemaValidationError < HorreumError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      messages = errors.map { |e| format_error(e) }.first(3)
      super("Schema validation failed: #{messages.join('; ')}")
    end

    private

    def format_error(error)
      path = error['data_pointer'] || error['schema_pointer'] || '/'
      type = error['type'] || 'validation'
      "#{type} at #{path}"
    end
  end
end
