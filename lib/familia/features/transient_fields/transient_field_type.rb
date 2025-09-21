# lib/familia/features/transient_fields/transient_field_type.rb

require 'familia/field_type'

require_relative 'redacted_string'

module Familia
  # TransientFieldType - Fields that are not persisted to database
  #
  # Transient fields automatically wrap values in RedactedString for security
  # and are excluded from serialization operations. They are ideal for storing
  # sensitive data like API keys, passwords, and tokens that should not be
  # persisted to the database.
  #
  # @example Using transient fields
  #   class SecretService < Familia::Horreum
  #     field :name                    # Regular field
  #     transient_field :api_key       # Wrapped in RedactedString
  #     transient_field :password      # Not persisted to database
  #   end
  #
  #   service = SecretService.new
  #   service.api_key = "sk-1234567890"
  #   service.api_key.class           #=> RedactedString
  #   service.to_h                    #=> {:name => nil} (no api_key)
  #
  class TransientFieldType < FieldType
    # Override setter to wrap values in RedactedString
    #
    # Values are automatically wrapped in RedactedString objects for security.
    # Nil values and existing RedactedString objects are handled appropriately.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_setter(klass)
      field_name = @name
      method_name = @method_name

      handle_method_conflict(klass, :"#{method_name}=") do
        klass.define_method :"#{method_name}=" do |value|
          wrapped = if value.nil?
                      nil
                    elsif value.is_a?(RedactedString)
                      value
                    else
                      RedactedString.new(value)
                    end
          instance_variable_set(:"@#{field_name}", wrapped)
        end
      end
    end

    # Override getter to unwrap RedactedString values
    #
    # Returns the actual value from the RedactedString wrapper for
    # convenient access, or nil if the value is nil or cleared.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_getter(klass)
      field_name = @name
      method_name = @method_name

      handle_method_conflict(klass, method_name) do
        klass.define_method method_name do
          wrapped = instance_variable_get(:"@#{field_name}")
          return nil if wrapped.nil? || wrapped.cleared?

          wrapped
        end
      end
    end

    # Override fast writer to disable it for transient fields
    #
    # Transient fields should not have fast writers since they're not
    # persisted to the database.
    #
    # @param _klass [Class] The class to define the method on
    #
    def define_fast_writer(_klass)
      # No fast writer for transient fields since they're not persisted
      Familia.ld "[TransientFieldType] Skipping fast writer for transient field: #{@name}"
      nil
    end

    # Transient fields are not persisted to database
    #
    # @return [Boolean] false - transient fields are never persisted
    #
    def persistent?
      false
    end

    # A convenience method that wraps `persistent?`
    #
    def transient?
      !persistent?
    end

    # Category for transient fields
    #
    # @return [Symbol] :transient
    #
    def category
      :transient
    end

    # Transient fields are not serialized to database
    #
    # This method should not be called since transient fields are not
    # persisted, but we provide it for completeness.
    #
    # @param value [Object] The value to serialize
    # @param record [Object] The record instance
    # @return [nil] Always nil since transient fields are not serialized
    #
    def serialize(_value, _record = nil)
      # Transient fields should never be serialized
      Familia.ld "[TransientFieldType] WARNING: serialize called on transient field #{@name}"
      nil
    end

    # Transient fields are not deserialized from database
    #
    # This method should not be called since transient fields are not
    # persisted, but we provide it for completeness.
    #
    # @param value [Object] The value to deserialize
    # @param record [Object] The record instance
    # @return [nil] Always nil since transient fields are not stored
    #
    def deserialize(_value, _record = nil)
      # Transient fields should never be deserialized
      Familia.ld "[TransientFieldType] WARNING: deserialize called on transient field #{@name}"
      nil
    end
  end
end
