# lib/familia/refinements/dear_json.rb

require 'familia/json_serializer'

module Familia
  module Refinements
    # DearJson provides standard JSON methods for core Ruby classes using
    # Familia's secure JsonSerializer (OJ in strict mode).
    #
    # This refinement allows developers to use the standard Ruby JSON interface
    # (as_json, to_json) on Hash and Array objects while ensuring all JSON
    # serialization goes through Familia's controlled, secure serialization.
    #
    # @example Basic usage with refinement
    #   using Familia::Refinements::DearJson
    #
    #   data = { user: user.as_json, tags: user.tags.as_json }
    #   json = data.to_json  # Uses Familia::JsonSerializer.dump
    #
    #   mixed_array = [user, user.tags, { meta: 'info' }]
    #   json = mixed_array.to_json  # Handles mixed Familia/core objects
    #
    # @example Without refinement (manual approach)
    #   data = { user: user.as_json, tags: user.tags.as_json }
    #   json = Familia::JsonSerializer.dump(data)
    #
    # Security Benefits:
    # - All JSON serialization uses OJ strict mode
    # - Prevents accidental exposure of sensitive objects
    # - Maintains Familia's security-first approach
    # - Provides familiar Ruby JSON interface
    #
    module DearJsonHashMethods
      # Convert hash to JSON string using Familia's secure JsonSerializer.
      # This method preprocesses the hash to handle Familia objects properly
      # by calling as_json on any objects that support it.
      #
      # @param options [Hash] Optional parameters (currently unused, for compatibility)
      # @return [String] JSON string representation
      #
      def to_json(options = nil)
        # Preprocess the hash to handle Familia objects
        processed_hash = transform_values do |value|
          if value.respond_to?(:as_json)
            value.as_json(options)
          else
            value
          end
        end

        Familia::JsonSerializer.dump(processed_hash)
      end

      # Convert hash to JSON-serializable representation.
      # This method recursively calls as_json on nested values to ensure
      # Familia objects are properly serialized in nested structures.
      #
      # @param options [Hash] Optional parameters (currently unused)
      # @return [Hash] A new hash with all values converted via as_json
      #
      def as_json(options = nil)
        # Create a new hash, calling as_json on each value.
        transform_values do |value|
          if value.respond_to?(:as_json)
            value.as_json(options)
          else
            value
          end
        end
      end
    end

    module DearJsonArrayMethods
      # Convert array to JSON string using Familia's secure JsonSerializer.
      # This method preprocesses the array to handle Familia objects properly
      # by calling as_json on any objects that support it.
      #
      # @param options [Hash] Optional parameters (currently unused, for compatibility)
      # @return [String] JSON string representation
      #
      def to_json(options = nil)
        # Preprocess the array to handle Familia objects
        processed_array = map do |item|
          if item.respond_to?(:as_json)
            item.as_json(options)
          else
            item
          end
        end

        Familia::JsonSerializer.dump(processed_array)
      end

      # Convert array to JSON-serializable representation.
      # This method recursively calls as_json on nested elements to ensure
      # Familia objects are properly serialized in nested structures.
      #
      # @param options [Hash] Optional parameters (currently unused)
      # @return [Array] A new array with all elements converted via as_json
      #
      def as_json(options = nil)
        # Create a new array, calling as_json on each element.
        map do |item|
          if item.respond_to?(:as_json)
            item.as_json(options)
          else
            item
          end
        end
      end
    end
    module DearJson
      refine Hash do
        import_methods DearJsonHashMethods
      end

      refine Array do
        import_methods DearJsonArrayMethods
      end
    end
  end
end
