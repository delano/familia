# lib/familia/features.rb

module Familia
  FeatureDefinition = Data.define(:name, :depends_on)

  # Familia::Features
  #
  module Features
    @features_enabled = nil
    attr_reader :features_enabled

    def feature(feature_name = nil, **options)
      @features_enabled ||= []

      return features_enabled if feature_name.nil?

      # If there's a value provied check that it's a valid feature
      feature_name = feature_name.to_sym
      unless Familia::Base.features_available.key?(feature_name)
        raise Familia::Problem, "Unsupported feature: #{feature_name}"
      end

      # If the feature is already available, do nothing but log about it
      if features_enabled.member?(feature_name)
        Familia.warn "[#{self.class}] feature already available: #{feature_name}"
        return
      end

      Familia.trace :FEATURE, nil, "#{self} includes #{feature_name.inspect}", caller(1..1) if Familia.debug?

      # Check dependencies and raise error if missing
      feature_def = Familia::Base.feature_definitions[feature_name]
      if feature_def&.depends_on&.any?
        missing = feature_def.depends_on - features_enabled
        if missing.any?
          raise Familia::Problem,
                "Feature #{feature_name} requires missing dependencies: #{missing.join(', ')}"
        end
      end

      # Add it to the list available features_enabled for Familia::Base classes.
      features_enabled << feature_name

      # Store feature options if any were provided using the new pattern
      if options.any?
        add_feature_options(feature_name, **options)
      end

      klass = Familia::Base.features_available[feature_name]

      # Extend the Familia::Base subclass (e.g. Customer) with the feature module
      include klass

      # NOTE: Do we want to extend Familia::DataType here? That would make it
      # possible to call safe_dump on relations fields (e.g. list, zset, hashkey).
      #
      # The challenge is that DataType classes (List, Set, etc.) are shared across
      # all Horreum models. If Customer extends DataType with safe_dump, then
      # Session's lists would also have it. Not ideal. If that's all we wanted
      # then we can do that by looping through every DataType class here.
      #
      # We'd need to extend the DataType instances for each Horreum subclass. That
      # avoids it getting included multiple times per DataType
    end
  end
end

# Load all feature files from the features directory
features_dir = File.join(__dir__, 'features')
Familia.ld "[DEBUG] Loading features from #{features_dir}"
if Dir.exist?(features_dir)
  Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
    Familia.ld "[DEBUG] Loading feature #{feature_file}"
    require_relative feature_file
  end
end
