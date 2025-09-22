# lib/familia/refinements/singularize.rb

module Familia
  module Refinements
    # Familia::Refinements::Singularize
    #
    # Converts a string from plural to singular form using basic English rules.
    #
    # @return [String] the singular version of the string
    #
    # @example Converting simple plurals
    #   "users".singularize #=> "user"
    #
    # @example Converting words ending in 'ies'
    #   "categories".singularize #=> "category"
    #
    # @example Converting words ending in 'es'
    #   "boxes".singularize #=> "box"
    #
    # @example Handling irregular cases
    #   "domains".singularize #=> "domain"
    module Singularize
      # We refine String to provide singularization functionality for converting
      # plural English words to their singular form. This uses basic English
      # pluralization rules and is suitable for most common cases in programming
      # contexts.
      #
      # Appropriate for converting collection names to item names, database
      # table names to model names, or any other singular identifier generation.
      # Note: This is a simplified implementation and may not handle all English
      # irregular plurals correctly.
      refine String do
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
      end
    end
  end
end
