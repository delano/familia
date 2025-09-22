# lib/familia/refinements/stylize_words.rb

module Familia
  module Refinements
    # Familia::Refinements::StylizeWords
    #
    # String transformation utilities for common naming convention conversions.
    # Provides camelCase/PascalCase, snake_case, and singularization methods.
    #
    # @example Converting to PascalCase/camelCase
    #   `"first_name".camelize` #=> "firstName"
    #   `"first_name".pascalize` #=> "FirstName"
    #
    # @example Converting to snake_case
    #   `"FirstName".snake_case` #=> "first_name"
    #
    # @example Singularization
    #   `"users".singularize` #=> "user"
    #   `"categories".singularize` #=> "category"
    #
    # @example Converting from kebab-case
    #   `"user-account".camelize` #=> "userAccount"
    #
    # @example Converting from mixed separators
    #   `"parse_html-document".pascalize` #=> "ParseHtmlDocument"
    #
    module StylizeWords
      # We refine String to provide comprehensive string transformation utilities
      # for common naming convention conversions. This includes PascalCase, camelCase
      # conversion, snake_case, and basic singularization.
      #
      # Appropriate for converting between naming conventions in Ruby applications,
      # API parameter conversion, database field/table name transformations,
      # and general identifier generation.
      refine String do
        # Convert to snake_case from PascalCase/camelCase
        #
        # Appropriate for converting Ruby class names to database table names, config
        # keys, part of a path or any other snake_case identifiers. The only situation
        # it is not appropriate for is investigating actual snakes.
        #
        # @return [String] the snake_case version of the string
        def snake_case
          split('::').last
                     .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
                     .gsub(/([a-z\\d])([A-Z])/, '\\1_\\2')
                     .downcase
        end

        # Convert from plural to singular form using basic English rules
        #
        # @return [String] the singular version of the string
        def singularize
          word = to_s
          # Basic English pluralization rules (simplified)
          if word.end_with?('ies')
            "#{word[0..-4]}y"
          elsif word.end_with?('es') && word.length > 3
            word[0..-3]
          elsif word.end_with?('s') && word.length > 1
            word[0..-2]
          else
            word
          end
        end

        # Convert to camelCase
        #
        # Use in the rare circumstance when you need the first word to not be capitalized.
        #
        # @return [String]
        def camelize
          _ize(:lower)
        end

        # Convert to PascalCase (alias for clarity)
        #
        # Use for module and class names.
        #
        # @return [String]
        def pascalize
          _ize(:upper)
        end

        private

        # Convert to camelCase or PascalCase
        #
        # @param first_letter [Symbol] :upper (default) for PascalCase, :lower for camelCase
        # @return [String] the stylized string
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
