# lib/familia/features.rb

module Familia

  module Features

    @features_enabled = nil
    attr_reader :features_enabled

    def feature(val = nil)
      @features_enabled ||= []

      # If there's a value provied check that it's a valid feature
      if val
        val = val.to_sym
        raise Familia::Problem, "Unsupported feature: #{val}" unless Familia::Base.features.key?(val)

        # If the feature is already enabled, do nothing but log about it
        if @features_enabled.member?(val)
          Familia.warn "[Familia::Settings] feature already enabled: #{val}"
          return
        end

        Familia.trace :FEATURE, nil, "#{self} includes #{val.inspect}", caller(1..1) if Familia.debug?

        klass = Familia::Base.features[val]

        # Extend the Familia::Base subclass (e.g. Customer) with the feature module
        include klass

        # NOTE: We may also want to extend Familia::DataType here so that we can
        # call safe_dump on relations fields (e.g. list, set, zset, hashkey). Or
        # maybe that only makes sense for hashk/object relations.
        #
        # We'd need to avoid it getting included multiple times (i.e. once for each
        # Familia::Horreum subclass that includes the feature).

        # Now that the feature is loaded successfully, add it to the list
        # enabled features for Familia::Base classes.
        @features_enabled << val
      end

      features_enabled
    end

  end

end

# Load all feature files from the features directory
features_dir = File.join(__dir__, 'features')
if Dir.exist?(features_dir)
  Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
    require_relative feature_file
  end
end
