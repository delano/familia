# lib/familia/horreum/related_fields.rb
#
# frozen_string_literal: true

module Familia

  RelatedFieldDefinition = Data.define(:name, :klass, :opts)

  class Horreum

    # Each related field needs some details from the parent (Horreum model)
    # in order to generate its dbkey. We use a parent proxy pattern to store
    # only essential parent information instead of full object reference. We
    # need only the model class and an optional unique identifier to generate
    # the dbkey; when the identifier is nil, we treat this as a class-level
    # relation (e.g. model_name:related_field_name); when the identifier
    # is not nil, we treat this as an instance-level relation
    # (model_name:identifier:related_field_name).
    #
    ParentDefinition = Data.define(:model_klass, :identifier) do
      # Factory method to create ParentDefinition from a parent instance
      def self.from_parent(parent_instance)
        case parent_instance
        when Class
          # Handle class-level relationships
          new(parent_instance, nil)
        else
          # Handle instance-level relationships
          identifier = parent_instance.respond_to?(:identifier) ? parent_instance.identifier : nil
          new(parent_instance.class, identifier)
        end
      end

      # Delegation methods for common operations needed by DataTypes
      def dbclient(uri = nil)
        model_klass.dbclient(uri)
      end

      def logical_database
        model_klass.logical_database
      end

      def dbkey(keystring = nil)
        if identifier
          # Instance-level relation: model_name:identifier:keystring
          model_klass.dbkey(identifier, keystring)
        else
          # Class-level relation: model_name:keystring
          model_klass.dbkey(keystring, nil)
        end
      end

      # Allow comparison with the original parent instance
      def ==(other)
        case other
        when ParentDefinition
          model_klass == other.model_klass && identifier == other.identifier
        when Class
          model_klass == other && identifier.nil?
        else
          # Compare with instance: check class and identifier match
          other.is_a?(model_klass) && other.respond_to?(:identifier) && identifier == other.identifier
        end
      end
      alias eql? ==
    end

    # RelatedFieldsManagement - Class-level methods for defining DataType relationships
    #
    # This module uses metaprogramming to dynamically create field definition methods
    # that generate both class-level and instance-level accessor methods for DataTypes
    # (e.g., list, set, zset, hashkey, string).
    #
    # When included in a class via ManagementMethods, it provides class methods like:
    # * Customer.list :recent_orders    # defines class method for class-level list
    # * customer.recent_orders          # creates instance method returning list instance
    #
    # Key metaprogramming features:
    # * Dynamically defines DSL methods for each Database type (e.g., set, list, hashkey)
    # * Each DSL method creates corresponding instance/class accessor methods
    # * Provides query methods for checking relation types
    #
    # Usage:
    #   Include this module in classes that need DataType management
    #   Call setup_related_fields_definition_methods to initialize the feature
    #
    module RelatedFieldsManagement
      # A practical flag to indicate that a Horreum member has relations,
      # not just theoretically but actually at least one list/haskey/etc.
      @has_related_fields = nil

      def self.included(base)
        base.extend(RelatedFieldsAccessors)
        base.setup_related_fields_definition_methods
      end

      # RelatedFieldsManagement::RelatedFieldsAccessors
      #
      module RelatedFieldsAccessors
        # Sets up all DataType related methods
        # This method generates the following for each registered DataType:
        #
        # Instance methods: set(), list(), hashkey(), sorted_set(), etc.
        # Query methods: set?(), list?(), hashkey?(), sorted_set?(), etc.
        # Collection methods: sets(), lists(), hashkeys(), sorted_sets(), etc.
        # Class methods: class_set(), class_list(), etc.
        #
        def setup_related_fields_definition_methods
          Familia::DataType.registered_types.each_pair do |kind, klass|
            Familia.trace :registered_types, kind, klass if Familia.debug?

            # Dynamically define instance-level relation methods
            #
            # Once defined, these methods can be used at the instance-level of a
            # Familia member to define *instance-level* relations to any of the
            # DataType types (e.g. set, list, hash, etc).
            #
            define_method :"#{kind}" do |*args|
              name, opts = *args

              # As log as we have at least one relation, we can set this flag.
              @has_related_fields = true

              attach_instance_related_field name, klass, opts
            end
            define_method :"#{kind}?" do |name|
              obj = related_fields[name.to_s.to_sym]
              !obj.nil? && klass == obj.klass
            end
            define_method :"#{kind}s" do
              names = related_fields.keys.select { |name| send(:"#{kind}?", name) }
              names.collect! { |name| related_fields[name] }
              names
            end

            # Dynamically define class-level relation methods
            #
            # Once defined, these methods can be used at the class-level of a
            # Familia member to define *class-level relations* to any of the
            # DataType types (e.g. class_set, class_list, class_hash, etc).
            #
            define_method :"class_#{kind}" do |*args|
              name, opts = *args
              attach_class_related_field name, klass, opts
            end
            define_method :"class_#{kind}?" do |name|
              obj = class_related_fields[name.to_s.to_sym]
              !obj.nil? && klass == obj.klass
            end
            define_method :"class_#{kind}s" do
              names = class_related_fields.keys.select { |name| send(:"class_#{kind}?", name) }
              # TODO: This returns instances of the DataType class which
              # also contain the options. This is different from the instance
              # DataTypes defined above which returns the Struct of name, klass, and opts.
              # names.collect! { |name| self.send name }
              # OR NOT:
              names.collect! { |name| class_related_fields[name] }
              names
            end
          end
        end
      end
      # End of RelatedFieldsAccessors module

      # Creates an instance-level relation
      def attach_instance_related_field(name, klass, opts)
        Familia.trace :attach_instance_related_field, name, klass, opts if Familia.debug?
        raise ArgumentError, "Name is blank (#{klass})" if name.to_s.empty?

        name = name.to_s.to_sym
        opts ||= {}

        related_fields[name] = RelatedFieldDefinition.new(name, klass, opts)

        # Create lazy-initializing accessor that calls initialize_relatives if needed
        define_method name do
          ivar = :"@#{name}"
          value = instance_variable_get(ivar)

          # If nil and we haven't initialized relatives, do it now
          # Check singleton class to avoid polluting instance variables
          if value.nil? && !singleton_class.instance_variable_defined?(:"@relatives_initialized")
            initialize_relatives
            value = instance_variable_get(ivar)
          end

          # If still nil after lazy initialization attempt, raise helpful error
          # Only raise if we tried to initialize but it's still nil
          if value.nil? && singleton_class.instance_variable_defined?(:"@relatives_initialized")
            raise "#{self.class}##{name} is nil. Did you override initialize without calling super? " \
                  "(Field is nil after initialization attempt)"
          end

          value
        end

        define_method :"#{name}=" do |val|
          send(name).replace val
        end
        define_method :"#{name}?" do
          !send(name).empty?
        end

        related_fields[name]
      end

      # Creates a class-level relation
      #
      # The DataType is built lazily on first access rather than at
      # declaration, so configure_related_field can still adjust the
      # definition between the class body and first use. The first access
      # freezes that definition's opts, closing the window for this field
      # only (Klass.instances is touched on every save and must not close it
      # for unrelated fields).
      def attach_class_related_field(name, klass, opts)
        Familia.trace :attach_class_related_field, "#{name} #{klass}", opts if Familia.debug?
        raise ArgumentError, 'Name is blank (klass)' if name.to_s.empty?

        name = name.to_s.to_sym
        opts = opts.nil? ? {} : opts.clone
        opts[:parent] = self unless opts.key?(:parent)

        class_related_fields[name] = RelatedFieldDefinition.new(name, klass, opts)

        define_singleton_method name do
          materialize_class_related_field(name)
        end

        define_singleton_method :"#{name}=" do |v|
          send(name).replace v
        end
        define_singleton_method :"#{name}?" do
          !send(name).empty?
        end

        class_related_fields[name]
      end

      # Reconfigures a related field after the class body has run.
      #
      # Lifecycle:
      # 1. Declare in the class body (`sorted_set :events, max_length: 100`).
      # 2. Reconfigure at boot, before any instance is created or the
      #    class-level collection is accessed.
      # 3. Frozen at first use: instance-level definitions freeze together at
      #    the end of the first initialize_relatives; each class-level
      #    definition freezes on its own first accessor call. A later call
      #    raises rather than leaving already-built DataTypes on old options.
      #
      # New declarations on a materialized class remain allowed (participation
      # relies on that); only reconfiguring a frozen definition is refused.
      #
      # @example Raise a cap at boot from configuration
      #   class Customer < Familia::Horreum
      #     sorted_set :events, max_length: 100
      #     class_sorted_set :registry
      #   end
      #   Customer.configure_related_field(:events, max_length: settings.events_cap)
      #   Customer.configure_related_field(:registry, max_length: 500)
      #
      # @param name [Symbol, String] the field name as declared
      # @param opts [Hash] options merged over the current definition's opts
      # @return [Familia::RelatedFieldDefinition] the replacement definition
      # @raise [ArgumentError] if the class has no such field, or the merged
      #   options would be rejected by the DataType constructor (same error
      #   class and message the constructor raises)
      # @raise [Familia::RelatedFieldFrozenError] if the definition has
      #   already been materialized
      def configure_related_field(name, **opts)
        name = name.to_s.to_sym

        related_fields_mutex.synchronize do
          registry = related_fields.key?(name) ? related_fields : class_related_fields
          raise ArgumentError, "#{self} has no related field #{name.inspect}" unless registry.key?(name)

          definition = registry[name]
          if definition.opts.frozen?
            scope = if registry.equal?(related_fields)
              "instance-level #{self}##{name}: instances already exist"
            else
              "class-level #{self}.#{name}: the collection was already built"
            end
            raise Familia::RelatedFieldFrozenError,
                  "Cannot reconfigure #{scope}. configure_related_field must run before first use."
          end

          merged = definition.opts.merge(opts)
          validate_related_field_opts!(merged, definition.klass)

          registry[name] = definition.with(opts: merged)
        end
      end

      private

      # Builds (once) and returns the class-level DataType for +name+.
      #
      # Double-checked under related_fields_mutex. Reads the CURRENT
      # definition from the registry so a configure_related_field call made
      # after the declaration is honored. Freezes the DataType (thread
      # safety: stub the class method, not the instance) and the definition's
      # opts. The keystring is the field name, not opts[:suffix], unchanged
      # from the eager build this replaces.
      def materialize_class_related_field(name)
        ivar = :"@#{name}"
        existing = instance_variable_get(ivar)
        return existing unless existing.nil?

        related_fields_mutex.synchronize do
          existing = instance_variable_get(ivar)
          next existing unless existing.nil?

          definition = class_related_fields.fetch(name) do
            raise ArgumentError, "#{self} has no class-level related field #{name.inspect}"
          end
          related_field = definition.klass.new(name, definition.opts)
          related_field.freeze
          definition.opts.freeze
          instance_variable_set(ivar, related_field)
        end
      end

      # Mirrors the eager checks in DataType#initialize so a bad option fails
      # at configuration time with the same error the constructor would
      # raise at first use. Unknown keys are deliberately NOT rejected:
      # DataType.valid_keys_only silently slices them at construction today,
      # and the registry keeps the full merged Hash (not the slice) so the
      # definition reflects exactly what was declared and configured.
      def validate_related_field_opts!(merged, klass)
        Familia.warn '[familia] :maxlength is ignored; rename to max_length:' if merged.key?(:maxlength)
        Familia::DataType.validate_max_length!(merged[:max_length], klass)
        Familia::DataType.validate_dirty_write_warnings!(merged[:dirty_write_warnings])
      end
    end
    # End of RelatedFieldsManagement module
  end
end
