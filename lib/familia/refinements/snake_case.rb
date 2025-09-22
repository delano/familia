# lib/familia/refinements/snake_case.rb

module Familia
  module Refinements
    # Familia::Refinements::StylizeWords
    #
    # Converts a string from PascalCase/camelCase to snake_case format.
    #
    # @return [String] the snake_case version of the string
    #
    # @example Converting simple CamelCase
    #   "FirstName".snake_case #=> "first_name"
    #
    # @example Converting PascalCase with acronyms
    #   XMLHttpRequest.name.snake_case #=> "xml_http_request"
    #
    # @example Converting namespaced class names
    #   "MyApp::UserAccount".snake_case #=> "user_account"
    #
    # @example Handling mixed case with numbers
    #   "parseHTML5Document".snake_case #=> "parse_html5_document"
    module SnakeCase
      # We refine String rather than Class or Module because this method operates on
      # string representations of class names (like those from `Class#name`) rather
      # than the class objects themselves. Refining String is safer because it
      # limits its scope to only the subset string manipulation contexts where it is
      # used.
      #
      # Appropriate for converting Ruby class names to database table names, config
      # keys, part of a path or any other snake_case identifiers. The only situation
      # it is not appropriate for is investigating actual snakes.
      refine String do
        def snake_case
          split('::').last
                     .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
                     .gsub(/([a-z\d])([A-Z])/, '\1_\2')
                     .downcase
        end
      end
    end
  end
end
