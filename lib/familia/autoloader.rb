# frozen_string_literal: true

module Familia
  # Provides autoloading functionality for Ruby files based on patterns and conventions.
  #
  # Used by the Features module at library startup to load feature files, and available
  # as a utility for other modules requiring file autoloading capabilities.
  module Autoloader
    # Autoloads Ruby files matching the given patterns.
    #
    # @param patterns [String, Array<String>] file patterns to match (supports Dir.glob patterns)
    # @param exclude [Array<String>] basenames to exclude from loading
    # @param log_prefix [String] prefix for debug logging messages
    def self.autoload_files(patterns, exclude: [], log_prefix: 'Autoloader')
      patterns = Array(patterns)

      patterns.each do |pattern|
        Dir.glob(pattern).each do |file_path|
          basename = File.basename(file_path)

          # Skip excluded files
          next if exclude.include?(basename)

          Familia.trace :FEATURE, nil, "[#{log_prefix}] Loading #{file_path}", caller(1..1) if Familia.debug?
          require File.expand_path(file_path)
        end
      end
    end

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
      features_dir = File.join(base_path, 'features')

      Familia.ld "[DEBUG] Autoloader loading features from #{features_dir}"

      return unless Dir.exist?(features_dir)

      # Use the shared autoload_files method
      autoload_files(
        File.join(features_dir, '*.rb'),
        log_prefix: 'Autoloader'
      )
    end
  end
end
