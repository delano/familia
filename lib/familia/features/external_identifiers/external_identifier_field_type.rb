# lib/familia/features/external_identifiers/external_identifier_field_type.rb

require 'familia/field_type'

module Familia
  module Features
    module ExternalIdentifiers
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
      #     feature :object_identifiers
      #     feature :external_identifiers
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
      class ExternalIdentifierFieldType < FieldType
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
              instance_variable_set(:"@#{field_name}", value)
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
    end
  end
end
