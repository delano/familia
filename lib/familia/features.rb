# lib/familia/features.rb

module Familia
  FeatureDefinition = Data.define(:name, :depends_on)

  # Familia::Features
  #
  module Features
    @features_enabled = nil
    @feature_options = nil
    attr_reader :features_enabled

    # Access feature options for a specific feature
    #
    # @param feature_name [Symbol] The feature name to get options for
    # @return [Hash] The options hash for the feature, or empty hash if none
    def feature_options(feature_name = nil)
      @feature_options ||= {}
      return @feature_options if feature_name.nil?

      @feature_options[feature_name.to_sym] || {}
    end

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

      # Auto-activate dependencies with cycle detection
      feature_def = Familia::Base.feature_definitions[feature_name]
      if feature_def&.depends_on&.any?
        @_activating_features ||= []
        if @_activating_features.include?(feature_name)
          raise Familia::Problem,
                "Cyclic feature dependency detected: #{(@_activating_features + [feature_name]).join(' -> ')}"
        end

        @_activating_features << feature_name
        begin
          missing = feature_def.depends_on - features_enabled
          missing.each do |dependency|
            if Familia.debug?
              Familia.trace :DEPENDENCY, nil, "#{self} auto-activating dependency #{dependency} for #{feature_name}",
                            caller(1..1)
            end
            feature(dependency) # Recursive call to activate dependency
          end
        ensure
          @_activating_features.delete(feature_name)
        end
      end

      # Add it to the list available features_enabled for Familia::Base classes.
      features_enabled << feature_name

      # Store feature options if any were provided
      if options.any?
        @feature_options ||= {}
        @feature_options[feature_name] = (@feature_options[feature_name] || {}).merge(options)
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
