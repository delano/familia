# frozen_string_literal: true

require_relative '../refinements/snake_case'

module Familia
  module Features
    # Enables automatic loading of feature-specific files when a feature is included in a user class.
    #
    # When included in a feature module, adds ClassMethods that detect when the feature is
    # included in user classes, derives the feature name, and autoloads files matching
    # conventional patterns in the user class's directory structure.
    module Autoloadable
      using Familia::Refinements::SnakeCase

      # Sets up a feature module with autoloading capabilities.
      #
      # Extends the feature module with ClassMethods and adds calling_location tracking
      # to detect where the feature gets included in user classes.
      #
      # @param feature_module [Module] the feature module being enhanced
      def self.included(feature_module)
        feature_module.extend(ClassMethods)

        # Add calling_location tracking to the feature module
        feature_module.instance_variable_set(:@calling_location, nil)

        feature_module.define_singleton_method(:calling_location) do
          @calling_location
        end

        feature_module.define_singleton_method(:calling_location=) do |location|
          @calling_location = location
        end
      end

      # Methods added to feature modules that include Autoloadable.
      module ClassMethods
        # Triggered when the feature is included in a user class.
        #
        # Detects the calling location, derives the feature name, and autoloads
        # feature-specific files based on conventional directory patterns.
        #
        # @param base [Class] the user class including this feature
        def included(base)
          super if defined?(super)

          # Store the calling location when the feature is included in a user class
          # Skip the first location which is the feature inclusion itself
          user_location = caller_locations.find { |loc| !loc.path.include?('lib/familia/') }
          self.calling_location = user_location&.path if user_location

          # Derive feature name from the module name
          feature_name = name.split('::').last.snake_case

          # Autoload feature-specific files
          if calling_location
            autoload_feature_files(calling_location, base, feature_name)
          end
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
          model_name = base.name.snake_case

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
      end
    end
  end
end
