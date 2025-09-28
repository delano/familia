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
    #   using Familia::DearJson
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
    module DearJson
      # Refine Hash to use Familia's JsonSerializer while maintaining
      # the standard Ruby JSON interface pattern.
      #
      refine Hash do
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
        # For Hash objects, this returns self since hashes are already JSON-compatible.
        # This method is provided for compatibility with the standard JSON pattern.
        #
        # @param options [Hash] Optional parameters (currently unused)
        # @return [Hash] The hash itself (already JSON-compatible)
        #
        def as_json(_options = nil)
          self
        end
      end

      # Refine Array to use Familia's JsonSerializer while maintaining
      # the standard Ruby JSON interface pattern.
      #
      refine Array do
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
        # For Array objects, this returns self since arrays are already JSON-compatible.
        # This method is provided for compatibility with the standard JSON pattern.
        #
        # @param options [Hash] Optional parameters (currently unused)
        # @return [Array] The array itself (already JSON-compatible)
        #
        def as_json(_options = nil)
          self
        end
      end
    end
  end
end
