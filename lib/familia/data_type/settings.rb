# lib/familia/data_type/settings.rb
#
# frozen_string_literal: true

module Familia
  class DataType
    # Settings - Instance-level configuration and introspection methods
    #
    # This module provides instance methods for accessing and managing
    # DataType object configuration, parent relationships, and serialization.
    #
    # Key features:
    # * Parent object relationship management
    # * URI and database configuration
    # * Serialization method delegation
    # * Type introspection
    #
    module Settings
      attr_reader :keystring, :opts, :logical_database
      attr_reader :uri

      alias url uri

      def class?
        !@opts[:class].to_s.empty? && @opts[:class].is_a?(Familia)
      end

      def parent_instance?
        parent&.is_a?(Horreum::ParentDefinition)
      end

      def parent_class?
        parent.is_a?(Class) && parent.ancestors.include?(Familia::Horreum)
      end

      def parent?
        parent_class? || parent_instance?
      end

      def parent
        # Return cached ParentDefinition if available
        return @parent if @parent

        # Return class-level parent if no instance parent
        return self.class.parent unless @parent_ref

        # Create ParentDefinition dynamically from stored reference.
        # This ensures we get the current identifier value (available after initialization)
        # rather than a stale nil value from initialization time. Cannot cache due to frozen object.
        Horreum::ParentDefinition.from_parent(@parent_ref)
      end

      def parent=(value)
        case value
        when Horreum::ParentDefinition
          @parent = value
        when nil
          @parent = nil
          @parent_ref = nil
        else
          # Store parent instance reference for lazy ParentDefinition creation.
          # During initialization, the parent's identifier may not be available yet,
          # so we defer ParentDefinition creation until first access for memory efficiency.
          # Note: @parent_ref is not cleared after use because DataType objects are frozen.
          @parent_ref = value
          @parent = nil  # Will be created dynamically in parent method
        end
      end

      def uri
        # Return explicit instance URI if set
        return @uri if @uri

        # If we have a parent with logical_database, build URI with that database
        if parent && parent.respond_to?(:logical_database) && parent.logical_database
          new_uri = (self.class.uri || Familia.uri).dup
          new_uri.db = parent.logical_database
          new_uri
        else
          # Fall back to class-level URI or global Familia.uri
          self.class.uri || Familia.uri
        end
      end

      def uri=(value)
        @uri = value
      end

      def dump_method
        self.class.dump_method
      end

      def load_method
        self.class.load_method
      end
    end
  end
end
