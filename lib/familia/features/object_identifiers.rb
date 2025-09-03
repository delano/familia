# lib/familia/features/object_identifiers.rb

module Familia
  module Features
    # ObjectIdentifiers is a feature that provides unique object identifier management
    # with configurable generation strategies. Object identifiers are crucial for
    # distinguishing objects in distributed systems and providing stable references.
    #
    # Object identifiers are:
    # - Unique across the system
    # - Persistent (stored in Redis/Valkey)
    # - Lazily generated (only when first accessed)
    # - Configurable (multiple generation strategies available)
    # - Preserved during initialization (existing IDs never regenerated)
    #
    # Generation Strategies:
    # - :uuid_v7 (default) - UUID version 7 with embedded timestamp for sortability
    # - :uuid_v4 - UUID version 4 for compatibility with legacy systems
    # - :hex - High-entropy hexadecimal identifier using SecureIdentifier
    # - Proc - Custom generation logic provided as a callable
    #
    # Example Usage:
    #
    #   # Default UUID v7 generation
    #   class User < Familia::Horreum
    #     feature :object_identifiers
    #     field :email
    #   end
    #
    #   user = User.new(email: 'user@example.com')
    #   user.objid  # => "01234567-89ab-7def-8000-123456789abc" (UUID v7)
    #
    #   # UUID v4 for legacy compatibility
    #   class LegacyUser < Familia::Horreum
    #     feature :object_identifiers, generator: :uuid_v4
    #     field :email
    #   end
    #
    #   legacy = LegacyUser.new(email: 'legacy@example.com')
    #   legacy.objid  # => "f47ac10b-58cc-4372-a567-0e02b2c3d479" (UUID v4)
    #
    #   # High-entropy hex for security-sensitive applications
    #   class SecureDocument < Familia::Horreum
    #     feature :object_identifiers, generator: :hex
    #     field :title
    #   end
    #
    #   doc = SecureDocument.new(title: 'Classified')
    #   doc.objid  # => "a1b2c3d4e5f6..." (256-bit hex)
    #
    #   # Custom generation strategy
    #   class TimestampedItem < Familia::Horreum
    #     feature :object_identifiers, generator: -> { "item_#{Time.now.to_i}_#{SecureRandom.hex(4)}" }
    #     field :data
    #   end
    #
    #   item = TimestampedItem.new(data: 'test')
    #   item.objid  # => "item_1693857600_a1b2c3d4"
    #
    # Data Integrity Guarantees:
    #
    # The feature preserves object identifiers passed during initialization,
    # ensuring that existing objects loaded from Redis maintain their IDs:
    #
    #   # Loading existing object from Redis preserves ID
    #   existing = User.new(objid: 'existing-uuid-value', email: 'existing@example.com')
    #   existing.objid  # => "existing-uuid-value" (preserved, not regenerated)
    #
    # Performance Characteristics:
    #
    # - Lazy Generation: IDs generated only when first accessed
    # - Thread-Safe: Generator strategy configured once during initialization
    # - Memory Efficient: No unnecessary ID generation for unused objects
    # - Redis Efficient: Only persists non-nil values to conserve memory
    #
    # Security Considerations:
    #
    # - UUID v7 includes timestamp information (may leak timing data)
    # - UUID v4 provides strong randomness without timing correlation
    # - Hex generator provides maximum entropy (256 bits) for security-critical use cases
    # - Custom generators allow domain-specific security requirements
    #
    module ObjectIdentifiers
      DEFAULT_GENERATOR = :uuid_v7

      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Ensure default generator is set in feature options
        base.add_feature_options(:object_identifiers, generator: DEFAULT_GENERATOR)

        # Register the objid field using a simple custom field type
        base.register_field_type(ObjectIdentifierFieldType.new(:objid, as: :objid, fast_method: false))
      end

      # Simplified ObjectIdentifierFieldType - inline instead of separate file
      class ObjectIdentifierFieldType < Familia::FieldType
        # Override getter to provide lazy generation with configured strategy
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
        def persistent?
          true
        end

        # Category for object identifier fields
        def category
          :object_identifier
        end
      end

      module ClassMethods
        # Generate a new object identifier using the configured strategy
        #
        # @return [String] A new unique identifier
        #
        def generate_objid
          options = feature_options(:object_identifiers)
          generator = options[:generator] || DEFAULT_GENERATOR

          case generator
          when :uuid_v7
            SecureRandom.uuid_v7
          when :uuid_v4
            SecureRandom.uuid_v4
          when :hex
            Familia.generate_hex_id
          when Proc
            generator.call
          else
            unless generator.respond_to?(:call)
              raise Familia::Problem, "Invalid object identifier generator: #{generator.inspect}"
            end

            generator.call

          end
        end

        # Find an object by its object identifier
        #
        # @param objid [String] The object identifier to search for
        # @return [Object, nil] The object if found, nil otherwise
        #
        def find_by_objid(objid)
          return nil if objid.to_s.empty?

          if Familia.debug?
            reference = caller(1..1).first
            Familia.trace :FIND_BY_OBJID, Familia.dbclient, objid, reference
          end

          # Use the object identifier as the key for lookup
          # This is a simple stub implementation - would need more sophisticated
          # search logic in a real application
          find_by_id(objid)
        rescue Familia::NotFound
          nil
        end
      end

      # Instance method for generating object identifier using configured strategy
      #
      # This method is called by the ObjectIdentifierFieldType when lazy generation
      # is needed. It uses the class-level generator configuration to create new IDs.
      #
      # @return [String] A newly generated unique identifier
      # @private
      #
      def generate_object_identifier
        self.class.generate_objid
      end

      # Alias for objid for consistency with naming conventions
      #
      # @return [String] The object identifier
      #
      def object_identifier
        objid
      end

      # Initialize object identifier configuration
      #
      # Called during object initialization to set up the ID generation strategy.
      # This hook is called AFTER field initialization, ensuring that any objid
      # values passed during construction are preserved.
      #
      def init
        super if defined?(super)

        # The generator strategy is configured at the class level via feature options.
        # We don't need to store it per-instance since it's consistent for the class.
        # The actual generation happens lazily in the getter when needed.

        return unless Familia.debug?

        options = self.class.feature_options(:object_identifiers)
        generator = options[:generator] || DEFAULT_GENERATOR
        Familia.trace :OBJID_INIT, dbclient, "Generator strategy: #{generator}", caller(1..1)
      end

      Familia::Base.add_feature self, :object_identifiers, depends_on: []
    end
  end
end
