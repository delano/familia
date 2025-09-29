# lib/familia/features/object_identifier.rb

module Familia
  module Features
    # ObjectIdentifier is a feature that provides unique object identifier management
    # with configurable generation strategies. Object identifiers are crucial for
    # distinguishing objects in distributed systems and providing stable references.
    #
    # Object identifiers are:
    # - Unique across the system
    # - Persistent (stored in Valkey/Redis)
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
    #     feature :object_identifier
    #     field :email
    #   end
    #
    #   user = User.new(email: 'user@example.com')
    #   user.objid  # => "01234567-89ab-7def-8000-123456789abc" (UUID v7)
    #
    #   # UUID v4 for legacy compatibility
    #   class LegacyUser < Familia::Horreum
    #     feature :object_identifier, generator: :uuid_v4
    #     field :email
    #   end
    #
    #   legacy = LegacyUser.new(email: 'legacy@example.com')
    #   legacy.objid  # => "f47ac10b-58cc-4372-a567-0e02b2c3d479" (UUID v4)
    #
    #   # High-entropy hex for security-sensitive applications
    #   class SecureDocument < Familia::Horreum
    #     feature :object_identifier, generator: :hex
    #     field :title
    #   end
    #
    #   doc = SecureDocument.new(title: 'Classified')
    #   doc.objid  # => "a1b2c3d4e5f6..." (256-bit hex)
    #
    #   # Custom generation strategy
    #   class TimestampedItem < Familia::Horreum
    #     feature :object_identifier, generator: -> { "item_#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
    #     field :data
    #   end
    #
    #   item = TimestampedItem.new(data: 'test')
    #   item.objid  # => "item_1693857600_a1b2c3d4"
    #
    # Data Integrity Guarantees:
    #
    # The feature preserves the object identifier passed during initialization,
    # ensuring that existing objects loaded from Valkey/Redis maintain their IDs:
    #
    #   # Loading existing object from Valkey/Redis preserves ID
    #   existing = User.new(objid: 'existing-uuid-value', email: 'existing@example.com')
    #   existing.objid  # => "existing-uuid-value" (preserved, not regenerated)
    #
    # Performance Characteristics:
    #
    # - Lazy Generation: IDs generated only when first accessed
    # - Thread-Safe: Generator strategy configured once during initialization
    # - Memory Efficient: No unnecessary ID generation for unused objects
    # - Valkey/Redis Efficient: Only persists non-nil values to conserve memory
    #
    # Security Considerations:
    #
    # - UUID v7 includes timestamp information (may leak timing data)
    # - UUID v4 provides strong randomness without timing correlation
    # - Hex generator provides maximum entropy (256 bits) for security-critical use cases
    # - Custom generators allow domain-specific security requirements
    #
    module ObjectIdentifier
      Familia::Base.add_feature self, :object_identifier, depends_on: []

      DEFAULT_GENERATOR = :uuid_v7

      def self.included(base)
        Familia.trace :LOADED, self, base if Familia.debug?
        base.extend ModelClassMethods

        # Ensure default generator is set in feature options
        base.add_feature_options(:object_identifier, generator: DEFAULT_GENERATOR)

        # Add class-level mapping for objid -> id lookups.
        #
        # If the model uses objid as it's primary key, this mapping will be
        # redundant to the builtin functionality of horreum clases, that
        # automatically populate ModelClass.instances sorted set. However,
        # if the model uses any other field as primary key, this mapping
        # is necessary to lookup objects by their objid.
        base.class_hashkey :objid_lookup

        # Register the objid field using a simple custom field type
        base.register_field_type(ObjectIdentifierFieldType.new(:objid, as: :objid, fast_method: false))
      end

      # ObjectIdentifierFieldType - Generate a unique object identifier
      #
      # Object identifier fields automatically generate unique identifiers when first
      # accessed if not already set. The generation strategy is configurable via
      # feature options. These fields preserve any values set during initialization
      # to ensure data integrity when loading existing objects from the database.
      #
      # The field type tracks the generator used for each objid to provide provenance
      # information for security-sensitive operations like external identifier generation.
      # This ensures that downstream features can validate the source and format of
      # object identifiers without relying on string pattern matching, which cannot
      # reliably distinguish between uuid7, uuid4, or hex formats in all cases.
      #
      # @example Using object identifier fields
      #   class User < Familia::Horreum
      #     feature :object_identifier, generator: :uuid_v7
      #   end
      #
      #   user = User.new
      #   user.objid  # Generates UUID v7 on first access
      #   user.objid_generator_used  # => :uuid_v7
      #
      #   # Loading existing object preserves ID but cannot determine original generator
      #   user2 = User.new(objid: "existing-uuid")
      #   user2.objid  # Returns "existing-uuid", not regenerated
      #   user2.objid_generator_used  # => nil (unknown provenance)
      #
      class ObjectIdentifierFieldType < Familia::FieldType
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

              # Track which generator was used for provenance
              options = self.class.feature_options(:object_identifier)
              generator = options[:generator] || DEFAULT_GENERATOR
              instance_variable_set(:"@#{field_name}_generator_used", generator)

              # Update mapping from objid to model primary key
              self.class.objid_lookup[generated_id] = identifier if respond_to?(:identifier) && identifier

              generated_id
            end
          end

          # Define getter for generator provenance tracking
          handle_method_conflict(klass, :"#{method_name}_generator_used") do
            klass.define_method :"#{method_name}_generator_used" do
              instance_variable_get(:"@#{field_name}_generator_used")
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
              # Remove old mapping if objid is changing
              old_value = instance_variable_get(:"@#{field_name}")
              if old_value && old_value != value
                Familia.logger.info("Removing objid mapping for #{old_value}")
                self.class.objid_lookup.remove_field(old_value)
              end

              instance_variable_set(:"@#{field_name}", value)

              # Update mapping from objid to this new identifier
              self.class.objid_lookup[value] = identifier unless value.nil?

              # When setting objid from external source (e.g., loading from Valkey/Redis),
              # we cannot determine the original generator, so we clear the provenance
              # tracking to indicate unknown origin. This prevents false assumptions
              # about the security properties of externally-provided identifiers.
              instance_variable_set(:"@#{field_name}_generator_used", nil)
            end
          end
        end

        # Object identifier fields are persisted to database
        #
        # @return [Boolean] true - An object identifier is always persisted
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

      module ModelClassMethods
        # Generate a new object identifier using the configured strategy
        #
        # @return [String] A new unique identifier
        #
        def generate_object_identifier
          options = feature_options(:object_identifier)
          generator = options[:generator] || DEFAULT_GENERATOR

          case generator
          when :uuid_v7
            SecureRandom.uuid_v7
          when :uuid_v4
            SecureRandom.uuid_v4
          when :hex
            Familia.generate_id(16)
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
            Familia.trace :FIND_BY_OBJID, nil, objid, reference
          end

          # Look up the primary ID from the external ID mapping
          primary_id = objid_lookup[objid]

          # If there is no mapping for this instance's objid, perhaps
          # the object dbkey is already using the objid.
          primary_id = objid if primary_id.nil?

          find_by_id(primary_id)
        rescue Familia::NotFound
          # If the object was deleted but mapping wasn't cleaned up
          # we could autoclean here, as long as we log it.
          # objid_lookup.remove_field(objid)
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
        self.class.generate_object_identifier
      end

      # Full-length alias for objid for clarity when needed
      #
      # @return [String] The object identifier
      #
      def object_identifier
        objid
      end

      # Full-length alias setter for objid
      #
      # @param value [String] The object identifier to set
      #
      def object_identifier=(value)
        self.objid = value
      end

      def destroy!
        # Clean up objid mapping when object is destroyed
        current_objid = instance_variable_get(:@objid)

        self.class.objid_lookup.remove_field(current_objid) if current_objid

        super if defined?(super)
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

        options = self.class.feature_options(:object_identifier)
        generator = options[:generator] || DEFAULT_GENERATOR
        Familia.trace :OBJID_INIT, nil, "Generator strategy: #{generator}"
      end
    end
  end
end
