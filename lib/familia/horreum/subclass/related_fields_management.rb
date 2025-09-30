# lib/familia/horreum/related_fields_management.rb

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
          other.is_a?(model_klass) && identifier == other.identifier
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
      @has_relations = nil

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
              @has_relations = true

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

        attr_reader name

        define_method :"#{name}=" do |val|
          send(name).replace val
        end
        define_method :"#{name}?" do
          !send(name).empty?
        end

        related_fields[name]
      end

      # Creates a class-level relation
      def attach_class_related_field(name, klass, opts)
        Familia.trace :attach_class_related_field, "#{name} #{klass}", opts if Familia.debug?
        raise ArgumentError, 'Name is blank (klass)' if name.to_s.empty?

        name = name.to_s.to_sym
        opts = opts.nil? ? {} : opts.clone
        opts[:parent] = self unless opts.key?(:parent)

        class_related_fields[name] = RelatedFieldDefinition.new(name, klass, opts)

        # An accessor method created in the metaclass will
        # access the instance variables for this class.
        singleton_class.attr_reader name

        define_singleton_method :"#{name}=" do |v|
          send(name).replace v
        end
        define_singleton_method :"#{name}?" do
          !send(name).empty?
        end

        related_field = klass.new name, opts
        related_field.freeze
        instance_variable_set(:"@#{name}", related_field)

        class_related_fields[name]
      end
    end
    # End of RelatedFieldsManagement module
  end
end
