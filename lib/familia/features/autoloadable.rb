# frozen_string_literal: true

module Familia
  module Features
    # Autoloadable provides automatic loading of feature-specific files
    # from user project directories when a feature is included in a model.
    #
    # Features that want to support autoloading should include this module.
    # When the feature is used via `feature :feature_name`, this module will
    # automatically search for and load files matching patterns like:
    #   - {model_name}/{feature_name}_*.rb
    #   - {model_name}/features/{feature_name}_*.rb
    #   - features/{feature_name}_*.rb
    #
    # Example:
    #   module SafeDump
    #     include Autoloadable
    #   end
    #
    #   class MegaCustomer < Familia::Horreum
    #     feature :safe_dump  # Will autoload mega_customer/safe_dump_*.rb
    #   end
    #
    module Autoloadable
      using Familia::Refinements::SnakeCase

      def self.included(base)
        # Derive feature name from the module name (e.g., SafeDump -> safe_dump)
        feature_name = name.split('::').last.snake_case

        # Get the stored calling location from feature options
        options = base.feature_options(feature_name.to_sym)
        calling_location = options[:calling_location]

        # Skip if no calling location (shouldn't happen, but safety check)
        return unless calling_location

        # Autoload feature-specific files
        autoload_feature_files(calling_location, base, feature_name)
      end

      private

      def self.autoload_feature_files(location_path, base, feature_name)
        base_dir = File.dirname(location_path)
        model_name = base.name.snake_case

        # Define search patterns for feature-specific files
        patterns = [
          File.join(base_dir, model_name, "#{feature_name}_*.rb"),
          File.join(base_dir, model_name, 'features', "#{feature_name}_*.rb"),
          File.join(base_dir, 'features', "#{feature_name}_*.rb"),
        ]

        Familia.trace :autoloadable, nil, "#{feature_name} patterns: #{patterns}", caller(1..1) if Familia.debug?
        Familia.ld "[Autoloadable] #{feature_name} searching: #{patterns}"

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
