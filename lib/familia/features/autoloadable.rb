# frozen_string_literal: true

require_relative '../refinements/snake_case'

module Familia
  module Features
    # Enables automatic loading of feature-specific files when a feature is included in a user class.
    #
    # When included in a feature module, adds ClassMethods that detect when the feature is
    # included in user classes, derives the feature name, and autoloads files matching
    # conventional patterns in the user class's directory structure.
    #
    # ## Extension Patterns
    #
    # Autoloadable supports two patterns for organizing feature extensions:
    #
    # ### 1. Module-based Extensions (Recommended)
    #
    # Create modules that are automatically included after file loading:
    #
    #   # customer/safe_dump_extensions.rb
    #   module Customer::SafeDumpExtensions
    #     def self.included(base)
    #       base.safe_dump_fields :name, :email, :created_at
    #       base.safe_dump_field :display_name, ->(c) { "#{c.name} <#{c.email}>" }
    #     end
    #
    #     def custom_method
    #       # Add instance methods here
    #     end
    #   end
    #
    # ### 2. Class Reopening (Deprecated)
    #
    # Directly reopen the class (generates deprecation warnings):
    #
    #   # customer/safe_dump_extensions.rb
    #   class Customer
    #     safe_dump_fields :name, :email  # Works but not recommended
    #   end
    #
    # ## Supported Module Naming Patterns
    #
    # - `ModelName::FeatureExtensions` (e.g., `Customer::SafeDumpExtensions`)
    # - `ModelName::Extensions::Feature` (e.g., `Customer::Extensions::SafeDump`)
    # - `ModelName::Feature` (e.g., `Customer::SafeDump`)
    #
    # ## File Organization Patterns
    #
    # Extension files are discovered using these patterns:
    # - `model_name/feature_name_*.rb`
    # - `model_name/features/feature_name_*.rb`
    # - `features/feature_name_*.rb`
    module Autoloadable
      using Familia::Refinements::SnakeCase

      # Sets up a feature module with autoloading capabilities.
      #
      # Extends the feature module with ClassMethods to handle post-inclusion autoloading.
      #
      # @param feature_module [Module] the feature module being enhanced
      def self.included(feature_module)
        feature_module.extend(ClassMethods)
      end

      # Methods added to feature modules that include Autoloadable.
      module ClassMethods
        # Triggered when the feature is included in a user class.
        #
        # Sets up for post-inclusion autoloading. The actual autoloading
        # is deferred until after feature setup completes.
        #
        # @param base [Class] the user class including this feature
        def included(base)
          # Call parent included method if it exists (defensive programming for mixed-in contexts)
          super if defined?(super)

          # No autoloading here - it's deferred to post_inclusion_autoload
          # to ensure the feature is fully set up before extension files are loaded
        end

        # Autoloads feature-specific files after a feature module is included.
        # The files are expected to live next to the file that defines +base+.
        #
        # @param base [Class] the class that just included the feature
        # @param feature_name [Symbol] the feature that was included
        # @param _options [Hash] ignored, kept for signature compatibility
        def post_inclusion_autoload(base, feature_name, _options = {})
          return unless base.name && !base.name.empty?

          file, = Module.const_source_location(base.name)

        # A cheap way to detect code that was not loaded from a real file on
        # disk (e.g. `ruby -e "puts 1"`, via IRB, or through eval).
          return if file.nil? || file.include?('-e') # skip eval/irb

          autoload_feature_files(file, base, feature_name.to_s.snake_case)
          include_extension_modules(base, feature_name.to_s.snake_case)
          check_for_deprecated_class_reopening(base, feature_name.to_s.snake_case)
        end

        private

        # Autoloads feature-specific files from conventional directory patterns.
        #
        # Searches for files matching patterns like:
        # - model_name/feature_name_*.rb
        # - model_name/features/feature_name_*.rb
        # - features/feature_name_*.rb
        #
        # @param location_path [String] path where the user class is defined
        # @param base [Class] the user class including the feature
        # @param feature_name [String] snake_case name of the feature
        def autoload_feature_files(location_path, base, feature_name)
          base_dir = File.dirname(location_path)

          # Handle anonymous classes gracefully
          model_name = base.name ? base.name.snake_case : "anonymous_#{base.object_id}"

          # Look for feature-specific files in conventional locations
          patterns = [
            File.join(base_dir, model_name, "#{feature_name}_*.rb"),
            File.join(base_dir, model_name, 'features', "#{feature_name}_*.rb"),
            File.join(base_dir, 'features', "#{feature_name}_*.rb"),
          ]

          # Use Autoloader's shared method for consistent file loading
          Familia::Autoloader.autoload_files(
            patterns,
            log_prefix: "Autoloadable(#{feature_name})"
          )
        end

        # Includes extension modules that match naming conventions after files are loaded.
        #
        # Looks for modules following patterns like:
        # - ModelName::FeatureExtensions (e.g., Customer::SafeDumpExtensions)
        # - ModelName::FeatureNameExtensions (e.g., Customer::SafeDumpExtensions)
        #
        # @param base [Class] the user class that included the feature
        # @param feature_name [String] snake_case name of the feature
        def include_extension_modules(base, feature_name)
          # Handle anonymous classes gracefully - log and skip if no valid class name
          unless base.name && !base.name.empty? && base.name.is_a?(String) && !base.name.include?('#<')
            Familia.trace(:FEATURE, nil,
              "Autoloadable(#{feature_name}) skipping module inclusion for anonymous/invalid class: #{base.inspect}",
              caller(1..1)) if Familia.debug?
            return
          end

          # Generate possible module names
          base_name = base.name
          feature_class_name = feature_name.split('_').map(&:capitalize).join

          possible_module_names = [
            "#{base_name}::#{feature_class_name}Extensions",
            "#{base_name}::Extensions::#{feature_class_name}",
            "#{base_name}::#{feature_class_name}"
          ]

          Familia.trace(:FEATURE, nil,
            "Autoloadable(#{feature_name}) searching for extension modules: #{possible_module_names.join(', ')}",
            caller(1..1)) if Familia.debug?

          possible_module_names.each do |module_name|
            begin
              extension_module = Object.const_get(module_name)

              # Verify it's actually a module
              if extension_module.is_a?(Module) && !extension_module.is_a?(Class)
                Familia.trace(:FEATURE, nil,
                  "Autoloadable(#{feature_name}) including #{module_name} in #{base_name}",
                  caller(1..1)) if Familia.debug?

                base.include(extension_module)
                return # Only include the first matching module
              end
            rescue NameError
              # Module doesn't exist, continue to next possibility
              next
            end
          end
        end

        # Checks for deprecated class-reopening patterns in loaded extension files.
        #
        # Scans the loaded extension files for class definitions that match the base class name,
        # which indicates use of the deprecated class-reopening pattern instead of modules.
        #
        # @param base [Class] the user class that included the feature
        # @param feature_name [String] snake_case name of the feature
        def check_for_deprecated_class_reopening(base, feature_name)
          # Handle anonymous classes gracefully - skip if no valid class name
          return unless base.name && !base.name.empty? && base.name.is_a?(String) && !base.name.include?('#<')

          file, = Module.const_source_location(base.name)
          return if file.nil?

          base_dir = File.dirname(file)
          model_name = base.name.snake_case

          # Check the same patterns we load for class definitions
          patterns = [
            File.join(base_dir, model_name, "#{feature_name}_*.rb"),
            File.join(base_dir, model_name, 'features', "#{feature_name}_*.rb"),
            File.join(base_dir, 'features', "#{feature_name}_*.rb"),
          ]

          patterns.each do |pattern|
            Dir.glob(pattern).each do |file_path|
              next unless File.exist?(file_path)

              content = File.read(file_path)

              # Look for class definitions that reopen the base class
              # Match patterns like "class ClassName" or "class Namespace::ClassName"
              class_pattern = /^[\s]*class\s+(?:\w+::)*#{Regexp.escape(base.name.split('::').last)}\s*(?:<|\n|$)/

              if content.match(class_pattern)
                Familia.warn "[DEPRECATION] File #{file_path} uses class-reopening pattern. " \
                            "Consider using module-based extensions instead. " \
                            "See: https://github.com/delano/familia/issues/102"
              end
            end
          end
        end
      end
    end
  end
end
