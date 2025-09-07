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

        # Called by the feature system after the feature is fully included.
        #
        # Uses const_source_location to determine where the base class is defined,
        # then autoloads feature-specific extension files from that location.
        #
        # @param base [Class] the class that included this feature
        # @param feature_name [Symbol] the name of the feature
        # @param options [Hash] feature options (unused but kept for compatibility)
        def post_inclusion_autoload(base, feature_name, options)
          Familia.trace :FEATURE, nil, "[Autoloadable] post_inclusion_autoload called for #{feature_name} on #{base.name || base}", caller(1..1) if Familia.debug?

          # Get the source location via Ruby's built-in introspection
          source_location = nil

          # Check for named classes that can be looked up via const_source_location
          # Class#name always returns String or nil, so type check is redundant
          if base.name && !base.name.empty?
            begin
              location_info = Module.const_source_location(base.name)
              source_location = location_info&.first
              Familia.trace :FEATURE, nil, "[Autoloadable] Source location for #{base.name}: #{source_location}", caller(1..1) if Familia.debug?
            rescue NameError => e
              # Handle cases where the class name is not a valid constant name
              # This can happen in test environments with dynamically created classes
              Familia.trace :FEATURE, nil, "[Autoloadable] Cannot resolve source location for #{base.name}: #{e.message}", caller(1..1) if Familia.debug?
            end
          else
            Familia.trace :FEATURE, nil, "[Autoloadable] Skipping source location detection - base.name=#{base.name.inspect}", caller(1..1) if Familia.debug?
          end

          # Autoload feature-specific files if we have a valid source location
          if source_location && !source_location.include?('-e') # Skip eval/irb contexts
            Familia.trace :FEATURE, nil, "[Autoloadable] Calling autoload_feature_files with #{source_location}", caller(1..1) if Familia.debug?
            autoload_feature_files(source_location, base, feature_name.to_s.snake_case)
          else
            Familia.trace :FEATURE, nil, "[Autoloadable] Skipping autoload - no valid source location", caller(1..1) if Familia.debug?
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
      end
    end
  end
end
