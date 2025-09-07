# frozen_string_literal: true

module Familia
  module Features
    module Autoloader
      def self.included(base)
        # Get the directory where the including module is defined
        # This should be lib/familia for the Features module
        base_path = File.dirname(caller_locations(1, 1).first.path)
        features_dir = File.join(base_path, 'features')

        Familia.ld "[DEBUG] Autoloader loading features from #{features_dir}"

        return unless Dir.exist?(features_dir)

        Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
          # Skip autoloader.rb to avoid circular loading
          next if File.basename(feature_file) == 'autoloader.rb'

          Familia.trace :FEATURE, nil, "Loading feature #{feature_file}", caller(1..1) if Familia.debug?
          require feature_file
        end
      end
    end
  end
end
