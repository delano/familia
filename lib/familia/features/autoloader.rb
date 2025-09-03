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
      def self.included(_base)
        # Get the file path of the module that's including us.
        # `caller_locations(1, 1).first` gives us the location where `include` was called.
        # This is a robust way to find the file path, especially for anonymous modules.
        calling_location = caller_locations(1, 1)&.first
        return unless calling_location

        including_file = calling_location.path

        # Find the features directory relative to the including file
        features_dir = File.join(File.dirname(including_file), 'features')

        Familia.ld "[DEBUG] Autoloader: Looking for features in #{features_dir}"

        if Dir.exist?(features_dir)
          Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
            Familia.ld "[DEBUG] Autoloader: Loading feature #{feature_file}"
            require feature_file
          end
        else
          Familia.ld "[DEBUG] Autoloader: No features directory found at #{features_dir}"
        end
      end
    end
  end
end
