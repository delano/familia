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
        val &&= val.to_sym
        raise Problem, "Unsupported feature: #{val}" unless Familia::Base.features.key?(val)

        # If the feature is already enabled, do nothing but log about it
        if @features_enabled.member?(val)
          Familia.warn "[Familia::Settings] feature already enabled: #{val}"
          return
        end

        klass = Familia::Base.features[val]

        # Extend the Familia::Base subclass (e.g. Customer) with the feature module
        self.send(:include, klass)

        # Also extend Familia::RedisType with the feature module so that
        # we can also call safe_dump on relations fields (e.g. list, set, zset, hashkey).
        #
        # TODO: Avoid this getting included multiple times (i.e. once for each
        # Familia::Horreum subclass that includes the feature). Then re-enable
        # this.
        #Familia::RedisType.send(:include, klass)

        # Now that the feature is loaded successfully, add it to the list
        # enabled features for Familia::Base classes.
        @features_enabled << val
      end

      features_enabled
    end

  end

end

require_relative 'features/safe_dump'
