# lib/familia/horreum/related_fields_management.rb

module Familia
  class Horreum
    #
    # RelatedFieldsManagement: Manages DataType fields and relations
    #
    # This module uses metaprogramming to dynamically create methods
    # for managing different types of Database objects (e.g., sets, lists, hashes).
    #
    # Key metaprogramming features:
    # * Dynamically defines methods for each Database type (e.g., set, list, hashkey)
    # * Creates both instance-level and class-level relation methods
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

        related_fields[name] = Struct.new(:name, :klass, :opts).new
        related_fields[name].name = name
        related_fields[name].klass = klass
        related_fields[name].opts = opts

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

        class_related_fields[name] = Struct.new(:name, :klass, :opts).new
        class_related_fields[name].name = name
        class_related_fields[name].klass = klass
        class_related_fields[name].opts = opts

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
