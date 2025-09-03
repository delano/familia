# lib/familia/features/external_identifier.rb

module Familia
  module Features
    # Familia::Features::ExternalIdentifier
    #
    module ExternalIdentifier
      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Ensure default prefix is set in feature options
        base.add_feature_options(:external_identifier, prefix: 'ext')

        # Add class-level mapping for extid -> id lookups
        base.class_hashkey :extid_lookup

        # Register the extid field using our custom field type
        base.register_field_type(ExternalIdentifierFieldType.new(:extid, as: :extid, fast_method: false))
      end

      # Error classes
      class ExternalIdentifierError < FieldTypeError; end

      # ExternalIdentifierFieldType - Fields that generate deterministic external identifiers
      #
      # External identifier fields generate shorter, public-facing identifiers that are
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
      #
      #   user = User.new(email: 'user@example.com')
      #   user.objid  # => "01234567-89ab-7def-8000-123456789abc"
      #   user.extid  # => "ext_abc123def456ghi789" (deterministic from objid)
      #
      #   # Same objid always produces same extid
      #   user2 = User.new(objid: user.objid, email: 'user@example.com')
      #   user2.extid  # => "ext_abc123def456ghi789" (identical to user.extid)
      #
      class ExternalIdentifierFieldType < Familia::FieldType
        # Override getter to provide lazy generation from objid
        #
        # Generates the external identifier deterministically from the object's
        # objid. This ensures consistency - the same objid will always produce
        # the same extid. Only generates when objid is available.
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

              # Generate external identifier from objid if available
              generated_extid = generate_external_identifier
              return unless generated_extid

              instance_variable_set(:"@#{field_name}", generated_extid)

              # Update mapping if we have an identifier
              if respond_to?(:identifier) && identifier
                self.class.extid_lookup[generated_extid] = identifier
              end

              generated_extid
            end
          end
        end

        # Override setter to preserve values during initialization
        #
        # This ensures that values passed during object initialization
        # (e.g., when loading from Redis) are preserved and not overwritten
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
              if old_value && old_value != value && respond_to?(:identifier)
                self.class.extid_lookup.del(old_value)
              end

              # Set the new value
              instance_variable_set(:"@#{field_name}", value)

              # Update mapping if we have both extid and identifier
              if value && respond_to?(:identifier) && identifier
                self.class.extid_lookup[value] = identifier
              end
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

      # ExternalIdentifier::ClassMethods
      #
      module ClassMethods
        def generate_extid(objid = nil)
          unless features_enabled.include?(:object_identifier)
            raise ExternalIdentifierError,
                  'ExternalIdentifier requires ObjectIdentifier feature'
          end
          return nil if objid.to_s.empty?

          objid_hex = objid.to_s.delete('-')
          external_part = Familia.shorten_to_external_id(objid_hex, base: 36)
          prefix = feature_options(:external_identifier)[:prefix] || 'ext'
          "#{prefix}_#{external_part}"
        end

        # Find an object by its external identifier
        #
        # @param extid [String] The external identifier to search for
        # @return [Object, nil] The object if found, nil otherwise
        #
        def find_by_extid(extid)
          return nil if extid.to_s.empty?

          if Familia.debug?
            reference = caller(1..1).first
            Familia.trace :FIND_BY_EXTID, Familia.dbclient, extid, reference
          end

          # Look up the primary ID from the external ID mapping
          primary_id = extid_lookup[extid]
          return nil if primary_id.nil?

          # Find the object by its primary ID
          find_by_id(primary_id)
        rescue Familia::NotFound
          # If the object was deleted but mapping wasn't cleaned up
          extid_lookup.del(extid)
          nil
        end
      end

      # Generate external identifier deterministically from objid
      def generate_external_identifier
        raise ExternalIdentifierError, 'missing objid field' unless respond_to?(:objid)

        current_objid = objid
        return nil if current_objid.nil? || current_objid.to_s.empty?

        # Convert objid to hex string for processing
        objid_hex = current_objid.delete('-') # Remove UUID hyphens if present

        # Generate deterministic external ID using SecureIdentifier
        external_part = Familia.shorten_to_external_id(objid_hex, base: 36)

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

      def init
        super if defined?(super)
        # External IDs are generated from objid, so no additional setup needed
      end

      def destroy!
        # Clean up extid mapping when object is destroyed
        current_extid = instance_variable_get(:@extid)
        self.class.extid_lookup.del(current_extid) if current_extid

        super if defined?(super)
      end

      Familia::Base.add_feature self, :external_identifier, depends_on: [:object_identifier]
    end
  end
end
