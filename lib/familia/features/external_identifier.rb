# lib/familia/features/external_identifier.rb

module Familia
  module Features
    # Familia::Features::ExternalIdentifier
    #
    module ExternalIdentifier
      Familia::Base.add_feature self, :external_identifier, depends_on: [:object_identifier]

      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ModelClassMethods

        # Ensure default prefix is set in feature options
        base.add_feature_options(:external_identifier, prefix: 'ext')

        # Add class-level mapping for extid -> id lookups
        base.class_hashkey :extid_lookup

        # Register the extid field using our custom field type
        base.register_field_type(ExternalIdentifierFieldType.new(:extid, as: :extid, fast_method: false))
      end

      # Error classes
      class ExternalIdentifierError < FieldTypeError; end

      # ExternalIdentifierFieldType - Fields that derive deterministic external identifiers
      #
      # External identifier fields derive shorter, public-facing identifiers that are
      # deterministically derived from object identifiers. These IDs are safe for use
      # in URLs, APIs, and other external contexts where shorter IDs are preferred.
      #
      # Key characteristics:
      # - Deterministic generation from objid ensures consistency
      # - Shorter than objid (128-bit vs 256-bit) for external use
      # - Base-36 encoding for URL-safe identifiers
      # - 'ext_' prefix for clear identification as external IDs
      # - Lazy generation preserves values from initialization
      #
      # @example Using external identifier fields
      #   class User < Familia::Horreum
      #     feature :object_identifier
      #     feature :external_identifier
      #     field :email
      #   end
      #   user = User.new(email: 'user@example.com')
      #   user.objid  # => "01234567-89ab-7def-8000-123456789abc"
      #   user.extid  # => "ext_abc123def456ghi789" (deterministic from objid)
      #   # Same objid always produces same extid
      #   user2 = User.new(objid: user.objid, email: 'user@example.com')
      #   user2.extid  # => "ext_abc123def456ghi789" (identical to user.extid)
      #
      class ExternalIdentifierFieldType < Familia::FieldType
        # Override getter to provide lazy generation from objid
        #
        # Derives the external identifier deterministically from the object's
        # objid. This ensures consistency - the same objid will always produce
        # the same extid. Only derives when objid is available.
        #
        # @param klass [Class] The class to define the method on
        #
        def define_getter(klass)
          field_name = @name
          method_name = @method_name

          handle_method_conflict(klass, method_name) do
            klass.define_method method_name do
              # Check if we already have a value (from initialization or previous generation)
              existing_value = instance_variable_get(:"@#{field_name}")
              return existing_value unless existing_value.nil?

              # Derive external identifier from objid if available
              derived_extid = derive_external_identifier
              return unless derived_extid

              instance_variable_set(:"@#{field_name}", derived_extid)

              # Update mapping if we have an identifier
              self.class.extid_lookup[derived_extid] = identifier if respond_to?(:identifier) && identifier

              derived_extid
            end
          end
        end

        # Override setter to preserve values during initialization
        #
        # This ensures that values passed during object initialization
        # (e.g., when loading from Valkey/Redis) are preserved and not overwritten
        # by the lazy generation logic.
        #
        # @param klass [Class] The class to define the method on
        #
        def define_setter(klass)
          field_name = @name
          method_name = @method_name

          handle_method_conflict(klass, :"#{method_name}=") do
            klass.define_method :"#{method_name}=" do |value|
              # Remove old mapping if extid is changing
              old_value = instance_variable_get(:"@#{field_name}")
              self.class.extid_lookup.remove_field(old_value) if old_value && old_value != value

              # UnsortedSet the new value
              instance_variable_set(:"@#{field_name}", value)

              # Update mapping if we have both extid and identifier
              return unless value && respond_to?(:identifier) && identifier

              self.class.extid_lookup[value] = identifier
            end
          end
        end

        # External identifier fields are persisted to database
        #
        # @return [Boolean] true - external identifiers are always persisted
        #
        def persistent?
          true
        end

        # Category for external identifier fields
        #
        # @return [Symbol] :external_identifier
        #
        def category
          :external_identifier
        end
      end

      # ExternalIdentifier::ModelClassMethods
      #
      module ModelClassMethods
        # Find an object by its external identifier
        #
        # @param extid [String] The external identifier to search for
        # @return [Object, nil] The object if found, nil otherwise
        #
        def find_by_extid(extid)
          return nil if extid.to_s.empty?

          if Familia.debug?
            reference = caller(1..1).first
            Familia.trace :FIND_BY_EXTID, nil, extid, reference
          end

          # Look up the primary ID from the external ID mapping
          primary_id = extid_lookup[extid]
          return nil if primary_id.nil?

          # Find the object by its primary ID
          find_by_id(primary_id)
        rescue Familia::NotFound
          # If the object was deleted but mapping wasn't cleaned up
          extid_lookup.remove_field(extid)
          nil
        end
      end

      # Derives a deterministic, public-facing external identifier from the object's
      # internal `objid`.
      #
      # This method uses the `objid`'s high-quality randomness to seed a
      # pseudorandom number generator (PRNG). The PRNG then acts as a complex,
      # deterministic function to produce a new identifier that has no discernible
      # mathematical correlation to the `objid`. This is a security measure to
      # prevent leaking information (like timestamps from UUIDv7) from the internal
      # identifier to the public one.
      #
      # The resulting identifier is always deterministic: the same `objid` will
      # always produce the same `extid`, which is crucial for lookups.
      #
      # @return [String, nil] A prefixed, base36-encoded external identifier, or nil
      #   if the `objid` is not present.
      # @raise [ExternalIdentifierError] if the `objid` provenance is unknown.
      def derive_external_identifier
        raise ExternalIdentifierError, 'Missing objid field' unless respond_to?(:objid)

        current_objid = objid
        return nil if current_objid.nil? || current_objid.to_s.empty?

        # Validate objid provenance for security guarantees
        validate_objid_provenance!

        # Normalize the objid to a consistent hex representation first.
        normalized_hex = normalize_objid_to_hex(current_objid)

        # Use the objid's randomness to create a deterministic, yet secure,
        # external identifier. We do not use SecureRandom here because the output
        # must be deterministic.
        #
        # The process is as follows:
        # 1. The objid (a high-entropy value) is hashed to create a uniform seed.
        # 2. The seed initializes a standard PRNG (Random.new).
        # 3. The PRNG acts as a deterministic function to generate a sequence of
        #    bytes that appears random, obscuring the original objid.

        # 1. Create a high-quality, uniform seed from the objid's entropy.
        seed = Digest::SHA256.digest(normalized_hex)

        # 2. Initialize a PRNG with the seed. The same seed will always produce
        #    the same sequence of "random" numbers.
        prng = Random.new(seed.unpack1('Q>'))

        # 3. Generate 16 bytes (128 bits) of deterministic output.
        random_bytes = prng.bytes(16)

        # Encode as a base36 string for a compact, URL-safe identifier.
        # 128 bits is approximately 25 characters in base36.
        external_part = random_bytes.unpack1('H*').to_i(16).to_s(36).rjust(25, '0')

        # Get prefix from feature options, default to "ext"
        options = self.class.feature_options(:external_identifier)
        prefix = options[:prefix] || 'ext'

        "#{prefix}_#{external_part}"
      end

      # Full-length alias for extid for clarity when needed
      #
      # @return [String] The external identifier
      #
      def external_identifier
        extid
      end

      # Full-length alias setter for extid
      #
      # @param value [String] The external identifier to set
      #
      def external_identifier=(value)
        self.extid = value
      end

      def destroy!
        # Clean up extid mapping when object is destroyed
        current_extid = instance_variable_get(:@extid)
        self.class.extid_lookup.remove_field(current_extid) if current_extid

        super if defined?(super)
      end

      private

      # Validate that objid comes from a known secure ObjectIdentifier generator
      #
      # This ensures we only derive external identifiers from objid values that
      # have known provenance and security properties. External identifiers derived
      # from objid values of unknown origin cannot provide security guarantees.
      #
      # @raise [ExternalIdentifierError] if objid has unknown provenance
      #
      def validate_objid_provenance!
        # Check if we have provenance information about the objid generator
        generator_used = objid_generator_used

        if generator_used.nil?
          error_msg = <<~MSG.strip
            Cannot derive external identifier: objid provenance unknown.
            External identifiers can only be derived from objid values created
            by the ObjectIdentifier feature to ensure security guarantees.
          MSG
          raise ExternalIdentifierError, error_msg
        end

        # Additional validation: ensure the ObjectIdentifier feature is active
        return if self.class.features_enabled.include?(:object_identifier)

        raise ExternalIdentifierError,
              'ExternalIdentifier requires ObjectIdentifier feature for secure provenance.'
      end

      # Normalize objid to hex format based on the known generator type
      #
      # Since we track which generator was used, we can safely normalize the objid
      # to hex format without relying on string pattern matching. This eliminates
      # the ambiguity between uuid7, uuid4, and hex formats.
      #
      # @param objid_value [String] The objid to normalize
      # @return [String] Hex string suitable for SecureIdentifier processing
      #
      def normalize_objid_to_hex(objid_value)
        generator_used = objid_generator_used

        case generator_used
        when :uuid_v7, :uuid_v4
          # UUID formats: remove hyphens to get 128-bit hex string
          objid_value.delete('-')
        when :hex
          # Already in hex format (256-bit)
          objid_value
        else
          # Custom generator: attempt to normalize, but we can't guarantee format
          normalized = objid_value.to_s.delete('-')
          unless normalized.match?(/\A[0-9a-fA-F]+\z/)
            error_msg = <<~MSG.strip
              Cannot normalize objid from custom generator #{generator_used}:
              value must be in hexadecimal format, got: #{objid_value}
            MSG
            raise ExternalIdentifierError, error_msg
          end
          normalized
        end
      end
    end
  end
end
