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
      def self.included(base)
        unless base.respond_to?(:config_name) # very loose guard for familia::base
          raise AutoloadError.new("Module #{base.name} does not respond to :config_name")
        end

        # Get the file path of the module that's including us.
        # `caller_locations(1, 1).first` gives us the location where `include` was called.
        # This is a robust way to find the file path, especially for anonymous modules.
        calling_location = caller_locations(1, 1)&.first
        return unless calling_location

        model_name = base.config_name # reduced to a single URL-safe, underscore-separated word
        including_file = calling_location.path
        including_file_dir = File.dirname(including_file)

        # Define the locations that we autoload from relative to
        # the directory of the including file.
        autoload_globs = define_autoload_globs(including_file_dir, model_name)

        Familia.ld "[DEBUG2] Autoloader: Looking for features in #{autoload_globs}"

        autoload_globs.each do |autoload_glob|
          # Will only load features if one or more file match. And won't raise
          # an error if the glob doesn't match any.
          filepaths = Dir.glob(autoload_glob)
          Familia.ld "[DEBUG] Autoloader: Found #{filepaths.size} with #{autoload_glob}"
          filepaths.each do |project_module|
            final_path = File.expand_path(project_module)
            Familia.ld "[DEBUG] Autoloader: Loading #{final_path}"
            require final_path
          end
        end

      end

      def self.define_autoload_globs(base_dir, model_name)
        [
          File.join(base_dir, model_name, '*.rb'),
          File.join(base_dir, 'features', '*.rb'),
          File.join(base_dir, model_name, 'feature_*.rb'),
          File.join(base_dir, model_name, 'features', '*.rb'),
        ]
      end
    end
  end
end
