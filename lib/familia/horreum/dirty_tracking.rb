# lib/familia/horreum/dirty_tracking.rb
#
# frozen_string_literal: true

require 'concurrent/map'

module Familia
  class Horreum
    # DirtyTracking - Tracks in-memory field changes since last save/refresh.
    #
    # Provides a minimal ActiveModel::Dirty-inspired API for detecting which
    # scalar fields have been modified. This is useful for:
    # - Knowing whether a save is needed
    # - Warning when collection writes happen with unsaved scalar changes
    # - Inspecting what changed and the old/new values
    #
    # Fields are marked dirty automatically by the setter defined in FieldType.
    # Dirty state is cleared after save, commit_fields, and refresh operations.
    #
    # Uses Concurrent::Map for thread-safe access to the dirty fields tracker
    # without requiring explicit mutex locks. The map is eagerly initialized
    # in Horreum#initialize and the allocate-based load paths so that no
    # lazy ||= race exists under normal usage. The ||= fallbacks in each
    # method are a safety net for subclasses that override initialize
    # without calling super (a documented anti-pattern).
    #
    # @example
    #   user = User.new(name: "Alice")
    #   user.dirty?            # => false (just initialized)
    #   user.name = "Bob"
    #   user.dirty?            # => true
    #   user.dirty?(:name)     # => true
    #   user.changed_fields    # => { name: ["Alice", "Bob"] }
    #   user.save
    #   user.dirty?            # => false
    #
    module DirtyTracking
      # Mark a field as dirty, recording its old value before the change.
      #
      # Called by the field setter in FieldType#define_setter. Only records
      # the original value on the first change (subsequent changes update
      # the current value but preserve the original baseline).
      #
      # @param field_name [Symbol] the field that changed
      # @param old_value [Object] the value before the change
      # @return [void]
      #
      def mark_dirty!(field_name, old_value)
        # Safety net for subclasses that override initialize without calling super
        @dirty_fields ||= Concurrent::Map.new
        # Atomic: only stores old_value if field_sym is not already tracked.
        @dirty_fields.put_if_absent(field_name.to_sym, old_value)
      end

      # Whether any fields (or a specific field) have unsaved changes.
      #
      # @param field [Symbol, String, nil] optional field to check
      # @return [Boolean]
      #
      def dirty?(field = nil)
        @dirty_fields ||= Concurrent::Map.new
        if field
          @dirty_fields.key?(field.to_sym)
        else
          !@dirty_fields.empty?
        end
      end

      # Returns the set of field names that have been modified.
      #
      # @return [Array<Symbol>] field names with unsaved changes
      #
      def dirty_fields
        @dirty_fields ||= Concurrent::Map.new
        @dirty_fields.keys
      end

      # Returns a hash of changed fields with [old_value, new_value] pairs.
      #
      # The old value is captured at the time of the first change since the
      # last clear. The new value is read from the current instance variable.
      #
      # @return [Hash{Symbol => Array(Object, Object)}]
      #
      def changed_fields
        @dirty_fields ||= Concurrent::Map.new
        result = {}
        @dirty_fields.each_pair do |field_name, old_value|
          current_value = instance_variable_get(:"@#{field_name}")
          result[field_name] = [old_value, current_value]
        end
        result
      end

      # Clears dirty tracking state for all or specific fields.
      #
      # Called automatically after save, commit_fields, and refresh.
      # When field names are provided, only those fields are cleared,
      # preserving dirty state for fields that were not persisted.
      #
      # @param field_names [Array<Symbol, String>] optional field names to clear.
      #   When empty, clears all dirty state (blanket reset).
      # @return [void]
      #
      def clear_dirty!(*field_names)
        @dirty_fields ||= Concurrent::Map.new
        if field_names.empty?
          @dirty_fields.clear
        else
          field_names.each { |f| @dirty_fields.delete(f.to_sym) }
        end
      end
    end
  end
end
