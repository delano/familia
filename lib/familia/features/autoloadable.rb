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
