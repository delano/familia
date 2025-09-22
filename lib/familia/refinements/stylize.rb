# lib/familia/refinements/stylize.rb

module Familia
  module Refinements
    # Familia::Refinements::Stylize
    #
    # Converts strings between snake_case/kebab-case and camelCase/PascalCase formats.
    #
    # Provides both `camelize` (lowercase first letter) and `pascalize` methods
    # for maximum clarity about the intended output format.
    #
    # @example Converting to PascalCase (default camelize)
    #   "first_name".camelize #=> "firstName"
    #   "first_name".pascalize #=> "FirstName"
    #
    # @example Converting from kebab-case
    #   "user-account".camelize #=> "userAccount"
    #
    # @example Converting from mixed separators
    #   "parse_html-document".pascalize #=> "ParseHtmlDocument"
    #
    # @example Handling single words
    #   "user".camelize #=> "User"
    #   "user".camelize(:lower) #=> "user"
    module Stylize
      # We refine String to provide camelization functionality for converting
      # snake_case or kebab-case strings to camelCase or PascalCase. This is
      # particularly useful for converting field names to class names or when
      # working with APIs that expect specific naming conventions.
      #
      # Appropriate for converting database field names to class names, API
      # parameter conversion, or any other camelCase/PascalCase identifier generation.
      refine String do
        # Convert to camelCase
        #
        # @return [String]
        def camelize
          _ize(:lower)
        end

        # Convert to PascalCase (alias for clarity)
        #
        # @return [String]
        def pascalize
          _ize(:upper)
        end

        private

        # Convert to camelCase or PascalCase
        #
        # @param first_letter [Symbol] :upper (default) for PascalCase, :lower for camelCase
        # @return [String] the camelized string
        def _ize(first_letter)
          case first_letter
          when :lower
            parts = split(/[_-]/)
            parts.first.downcase + parts[1..].map(&:capitalize).join
          when :upper
            split(/[_-]/).map(&:capitalize).join
          else
            raise ArgumentError, "Uknown stylization in first_letter: #{first_letter}"
          end
        end
      end
    end
  end
end
