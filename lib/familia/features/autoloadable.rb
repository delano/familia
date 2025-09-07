# frozen_string_literal: true

require_relative '../refinements/snake_case'

module Familia
  module Features
    module Autoloadable
      using Familia::Refinements::SnakeCase

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

      module ClassMethods
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

        def autoload_feature_files(location_path, base, feature_name)
          base_dir = File.dirname(location_path)
          model_name = base.name.snake_case

          # Look for feature-specific files in conventional locations
          patterns = [
            File.join(base_dir, model_name, "#{feature_name}_*.rb"),
            File.join(base_dir, model_name, 'features', "#{feature_name}_*.rb"),
            File.join(base_dir, 'features', "#{feature_name}_*.rb"),
          ]

          patterns.each do |pattern|
            Dir.glob(pattern).each do |file|
              Familia.ld "[Autoloadable] Loading #{file} for #{feature_name}"
              require File.expand_path(file)
            end
          end
        end
      end
    end
  end
end
