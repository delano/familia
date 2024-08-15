# rubocop:disable all

module Familia

  @features_enabled = nil

  module Features

    attr_reader :features_enabled

    def feature(val = nil)
      @features_enabled ||= []

      Familia.ld "[Familia::Settings] feature: #{val.inspect}"

      # If there's a value provied check that it's a valid feature
      if val
        val = val.to_sym
        raise Familia::Problem, "Unsupported feature: #{val}" unless Familia::Base.features.key?(val)

        # If the feature is already enabled, do nothing but log about it
        if @features_enabled.member?(val)
          Familia.warn "[Familia::Settings] feature already enabled: #{val}"
          return
        end

        klass = Familia::Base.features[val]

        # Extend the Familia::Base subclass (e.g. Customer) with the feature module
        include klass

        # NOTE: We may also want to extend Familia::RedisType here so that we can
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

require_relative 'features/safe_dump'
