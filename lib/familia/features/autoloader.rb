# lib/familia/features/autoloader.rb

module Familia
  module Features
    # Autoloader is a mixin that automatically loads feature files from a 'features'
    # subdirectory when included. This provides a standardized way to organize and
    # auto-load project-specific features.
    #
    # When included in a module, it automatically:
    # 1. Determines the directory containing the module file
    # 2. Looks for a 'features' subdirectory in that location
    # 3. Loads all *.rb files from that features directory
    #
    # Example usage:
    #
    #   # apps/api/v2/models/customer/features.rb
    #   module V2
    #     class Customer < Familia::Horreum
    #       module Features
    #         include Familia::Features::Autoloader
    #         # Automatically loads all files from customer/features/
    #       end
    #     end
    #   end
    #
    # This would automatically load:
    #   - apps/api/v2/models/customer/features/deprecated_fields.rb
    #   - apps/api/v2/models/customer/features/legacy_support.rb
    #   - etc.
    #
    module Autoloader

      using Familia::Refinements::SnakeCase

      def self.included(base)
        # Get the file path of the module that's including us.
        # `caller_locations(1, 1).first` gives us the location where `include` was called.
        # This is a robust way to find the file path, especially for anonymous modules.
        calling_location = caller_locations(1, 1)&.first
        return unless calling_location

        # Define the locations that we autoload from relative to
        # the directory of the including file.
        autoload_globs = define_autoload_globs(calling_location, base)

        Familia.trace :autoloader, nil, "Looking in #{autoload_globs}", caller(1..1) if Familia.debug?

        autoload_globs.each do |autoload_glob|
          # Will only load features if one or more file match. And won't raise
          # an error if the glob doesn't match any.
          filepaths = Dir.glob(autoload_glob)

          Familia.trace :autoloader, nil, "Found #{filepaths.size} files with #{autoload_glob}", caller(1..1) if Familia.debug?

          filepaths.each do |project_module|
            final_path = File.expand_path(project_module)
            Familia.ld "[DEBUG] Autoloader: loading #{final_path}"
            require final_path
          end
        end

      end

      def self.define_autoload_globs(location, base)
        # A very loose guard for friends of the family
        raise AutoloadError.new("Module #{base} does not respond to :name") unless base.respond_to?(:name)

        # Guard for calling location path
        raise AutoloadError.new("Location does not respond to :path") unless location.respond_to?(:path)

        # Reduced the class to a single URL-safe, underscore-separated word
        model_name = base.name.snake_case

        including_filepath = location.path
        base_dir = File.dirname(including_filepath)
        [
          File.join(base_dir, model_name, 'features.rb'),
          File.join(base_dir, 'features', '*.rb'),
          File.join(base_dir, model_name, 'feature_*.rb'),
          File.join(base_dir, model_name, 'features', '*.rb'),
        ]
      end
    end
  end
end
