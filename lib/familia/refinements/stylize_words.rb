# lib/familia/refinements/stylize_words.rb
#
# frozen_string_literal: true

module Familia
  module Refinements
    # Core string transformation methods that can be tested directly
    module StylizeWordsMethods
      # 'Models::Participants' -> 'Participants'
      def demodularize
        split('::').last
      end

      # Convert to snake_case from PascalCase/camelCase
      def snake_case
        gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
          .gsub(/([a-z\\d])([A-Z])/, '\\1_\\2')
          .downcase
      end

      # Convert to camelCase
      def camelize
        _ize(:lower)
      end

      # Convert to PascalCase
      def pascalize
        _ize(:upper)
      end

      private

      def _ize(first_letter)
        case first_letter
        when :lower
          parts = split(/[_-]/)
          parts.first.downcase + parts[1..].map(&:capitalize).join
        when :upper
          split(/[_-]/).map(&:capitalize).join
        else
          raise ArgumentError, "Unknown stylization in first_letter: #{first_letter}"
        end
      end
    end

    # Refinement that delegates to the testable methods
    module StylizeWords
      refine String do
        import_methods StylizeWordsMethods
      end
    end
  end
end
