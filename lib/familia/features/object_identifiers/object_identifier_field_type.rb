# lib/familia/features/object_identifiers/object_identifier_field_type.rb

require 'familia/field_type'

module Familia
  module Features
    module ObjectIdentifiers
      # ObjectIdentifierFieldType - Fields that generate unique object identifiers
      #
      # Object identifier fields automatically generate unique identifiers when first
      # accessed if not already set. The generation strategy is configurable via
      # feature options. These fields preserve any values set during initialization
      # to ensure data integrity when loading existing objects from Redis.
      #
      # @example Using object identifier fields
      #   class User < Familia::Horreum
      #     feature :object_identifiers, generator: :uuid_v7
      #   end
      #
      #   user = User.new
      #   user.objid  # Generates UUID v7 on first access
      #
      #   # Loading existing object preserves ID
      #   user2 = User.new(objid: "existing-uuid")
      #   user2.objid  # Returns "existing-uuid", not regenerated
      #
      class ObjectIdentifierFieldType < FieldType
        # Override getter to provide lazy generation with configured strategy
        #
        # Generates the identifier using the configured strategy if not already set.
        # This preserves any values set during initialization while providing
        # automatic generation for new objects.
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

              # Generate new identifier using configured strategy
              generated_id = generate_object_identifier
              instance_variable_set(:"@#{field_name}", generated_id)
              generated_id
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

        # Object identifier fields are persisted to database
        #
        # @return [Boolean] true - object identifiers are always persisted
        #
        def persistent?
          true
        end

        # Category for object identifier fields
        #
        # @return [Symbol] :object_identifier
        #
        def category
          :object_identifier
        end
      end
    end
  end
end
