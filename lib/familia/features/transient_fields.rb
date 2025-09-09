# lib/familia/features/transient_fields.rb

require_relative 'transient_fields/redacted_string'

module Familia
  module Features
    # TransientFields is a feature that provides secure handling of sensitive runtime data
    # that should never be persisted to Redis/Valkey. Unlike encrypted fields, transient
    # fields exist only in memory and are automatically wrapped in RedactedString objects
    # for security.
    #
    # Transient fields are ideal for:
    # - API keys and tokens that change frequently
    # - Temporary passwords or passphrases
    # - Session-specific secrets
    # - Any sensitive data that should never touch persistent storage
    # - Debug or development secrets that need secure handling
    #
    # All transient field values are automatically wrapped in RedactedString instances
    # which provide:
    # - Automatic redaction in logs and string representations
    # - Secure memory management with explicit cleanup
    # - Safe access patterns through expose blocks
    # - Protection against accidental value exposure
    #
    # Example:
    #
    #   class ApiClient < Familia::Horreum
    #     feature :transient_fields
    #
    #     field :endpoint          # Regular persistent field
    #     transient_field :token   # Transient field (not persisted)
    #     transient_field :secret, as: :api_secret  # Custom accessor name
    #   end
    #
    #   client = ApiClient.new(
    #     endpoint: 'https://api.example.com',
    #     token: ENV['API_TOKEN'],
    #     secret: ENV['API_SECRET']
    #   )
    #
    #   # Regular field persists
    #   client.save
    #   client.endpoint  # => "https://api.example.com"
    #
    #   # Transient fields are RedactedString instances
    #   puts client.token  # => "[REDACTED]"
    #
    #   # Access the actual value safely
    #   client.token.expose do |token|
    #     response = HTTP.post(client.endpoint,
    #       headers: { 'Authorization' => "Bearer #{token}" }
    #     )
    #     # Token value is only available within this block
    #   end
    #
    #   # Explicit cleanup when done
    #   client.token.clear!
    #
    # Security Features:
    #
    # RedactedString automatically protects sensitive values:
    # - String representation shows "[REDACTED]" instead of actual value
    # - Inspect output shows "[REDACTED]" instead of actual value
    # - Hash values are constant to prevent value inference
    # - Equality checks work only on object identity
    #
    # Safe Access Patterns:
    #
    #   # ✅ Recommended: Use .expose block
    #   client.token.expose do |token|
    #     # Use token directly without creating copies
    #     HTTP.auth("Bearer #{token}")  # Safe
    #   end
    #
    #   # ✅ Direct access (use carefully)
    #   raw_token = client.token.value
    #   # Remember to clear original source if needed
    #
    #   # ❌ Avoid: These create uncontrolled copies
    #   token_copy = client.token.value.dup      # Creates copy in memory
    #   interpolated = "Bearer #{client.token}"  # Creates copy via to_s
    #
    # Memory Management:
    #
    #   # Clear individual fields
    #   client.token.clear!
    #
    #   # Check if cleared
    #   client.token.cleared?  # => true
    #
    #   # Accessing cleared values raises error
    #   client.token.value  # => SecurityError: Value already cleared
    #
    # ⚠️ Important Security Limitations:
    #
    # Ruby provides NO memory safety guarantees for cryptographic secrets:
    # - No secure wiping: .clear! is best-effort only
    # - GC copying: Garbage collector may duplicate secrets
    # - String operations: Every manipulation creates copies
    # - Memory persistence: Secrets may remain in memory indefinitely
    #
    # For highly sensitive applications, consider external secrets management
    # (HashiCorp Vault, AWS Secrets Manager) or languages with secure memory handling.
    #
    module TransientFields

      Familia::Base.add_feature self, :transient_fields, depends_on: nil

      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Initialize transient fields tracking
        base.instance_variable_set(:@transient_fields, []) unless base.instance_variable_defined?(:@transient_fields)
      end

      module ClassMethods
        # Define a transient field that automatically wraps values in RedactedString
        #
        # Transient fields are not persisted to Redis/Valkey and exist only in memory.
        # All values are automatically wrapped in RedactedString for security.
        #
        # @param name [Symbol] The field name
        # @param as [Symbol] The method name (defaults to field name)
        # @param kwargs [Hash] Additional field options
        #
        # @example Define a transient API key field
        #   class Service < Familia::Horreum
        #     feature :transient_fields
        #     transient_field :api_key
        #   end
        #
        # @example Define a transient field with custom accessor name
        #   class Service < Familia::Horreum
        #     feature :transient_fields
        #     transient_field :secret_key, as: :api_secret
        #   end
        #
        #   service = Service.new(secret_key: 'secret123')
        #   service.api_secret.expose { |key| use_api_key(key) }
        #
        def transient_field(name, as: name, **kwargs)
          @transient_fields ||= []
          @transient_fields << name unless @transient_fields.include?(name)

          # Use the field type system for proper integration
          require_relative 'transient_fields/transient_field_type'
          field_type = TransientFieldType.new(name, as: as, **kwargs.merge(fast_method: false))
          register_field_type(field_type)
        end

        # Returns list of transient field names defined on this class
        #
        # @return [Array<Symbol>] Array of transient field names
        #
        def transient_fields
          @transient_fields || []
        end

        # Check if a field is transient
        #
        # @param field_name [Symbol] The field name to check
        # @return [Boolean] true if field is transient, false otherwise
        #
        def transient_field?(field_name)
          transient_fields.include?(field_name.to_sym)
        end
      end

      # Clear all transient fields for this instance
      #
      # This method iterates through all defined transient fields and calls
      # clear! on each RedactedString instance. Use this for cleanup when
      # the object is no longer needed.
      #
      # @return [void]
      #
      # @example Clear all secrets when done
      #   client = ApiClient.new(token: 'secret', api_key: 'key123')
      #   # ... use client ...
      #   client.clear_transient_fields!
      #   client.token.cleared?  # => true
      #
      def clear_transient_fields!
        self.class.transient_fields.each do |field_name|
          field_value = instance_variable_get("@#{field_name}")
          field_value.clear! if field_value.respond_to?(:clear!)
        end
      end

      # Check if all transient fields have been cleared
      #
      # @return [Boolean] true if all transient fields are cleared, false otherwise
      #
      def transient_fields_cleared?
        self.class.transient_fields.all? do |field_name|
          field_value = instance_variable_get("@#{field_name}")
          field_value.nil? || (field_value.respond_to?(:cleared?) && field_value.cleared?)
        end
      end

      # Returns a hash of transient field names and their redacted representations
      #
      # This method is useful for debugging and logging as it shows which transient
      # fields are defined without exposing their actual values.
      #
      # @return [Hash] Hash with field names as keys and "[REDACTED]" as values
      #
      # @example Check transient field status
      #   client.transient_fields_summary
      #   # => { token: "[REDACTED]", api_key: "[REDACTED]" }
      #
      def transient_fields_summary
        self.class.transient_fields.each_with_object({}) do |field_name, summary|
          field_value = instance_variable_get("@#{field_name}")
          summary[field_name] = if field_value.nil?
                                  nil
                                elsif field_value.respond_to?(:cleared?) && field_value.cleared?
                                  '[CLEARED]'
                                else
                                  '[REDACTED]'
                                end
        end
      end

    end
  end
end
