# lib/familia/features/autoloader.rb

# rubocop:disable Style/ClassAndModuleChildren
module Familia::Features
  # Provides autoloading functionality for Ruby files based on patterns and conventions.
  #
  # Used by the Features module at library startup to load feature files, and available
  # as a utility for other modules requiring file autoloading capabilities.
  module Autoloader
    using Familia::Refinements::StylizeWords

    # Autoloads feature files when this module is included.
    #
    # Discovers and loads all Ruby files in the features/ directory relative to the
    # including module's location. Typically used by Familia::Features.
    #
    # @param base [Module] the module including this autoloader
    def self.included(base)
      # Get the directory where the including module is defined
      # This should be lib/familia for the Features module
      base_path = File.dirname(caller_locations(1, 1).first.path)
      config_name = normalize_to_config_name(base.name)

      dir_patterns = [
        File.join(base_path, 'features', '*.rb'),
        File.join(base_path, config_name, 'features', '*.rb'),
        File.join(base_path, config_name, 'features.rb'),
      ]

      # Ensure the Features module exists within the base module
      unless base.const_defined?(:Features) || config_name.eql?('features')
        base.const_set(:Features, Module.new)
      end

      # Use the shared autoload_files method
      autoload_files(dir_patterns, log_prefix: "Autoloader[#{config_name}]")
    end

    # Autoloads Ruby files matching the given patterns.
    #
    # @param patterns [String, Array<String>] file patterns to match (supports Dir.glob patterns)
    # @param exclude [Array<String>] basenames to exclude from loading
    # @param log_prefix [String] prefix for debug logging messages
    def self.autoload_files(patterns, exclude: [], log_prefix: 'Autoloader')
      patterns = Array(patterns)

      patterns.each do |pattern|
        Familia.trace :AUTOLOAD, nil, "[#{log_prefix}] Autoloader loading features from #{pattern}"
        Dir.glob(pattern).each do |file_path|
          basename = File.basename(file_path)

          # Skip excluded files
          next if exclude.include?(basename)

          Familia.trace :FEATURE, nil, "[#{log_prefix}] Loading #{basename}" if Familia.debug?
          require File.expand_path(file_path)
        end
      end
    end

    class << self
      # Converts the value into a string that can be used to look up configuration
      # values or system paths. This replicates the normalization done by the
      # Familia::Horreum model class config_name method.
      #
      # @see Familia::Horreum::DefinitionMethods#config_name
      #
      # NOTE: We don't call that existing method directly b/c Autoloader is meant
      # to work for any class/module that matches `dir_patterns` (see `included`).
      #
      # @param value [String] the value to normalize (typically a class name)
      # @return [String] the underscored value as a string
      def normalize_to_config_name(value)
        return nil if value.nil?

        value.demodularize.snake_case
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
