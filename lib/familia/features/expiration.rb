# rubocop:disable all
# frozen_string_literal: true


module Familia::Features

  module Expiration
    @ttl = nil

    module ClassMethods

      attr_writer :ttl

      def ttl(v = nil)
        @ttl = v.to_f unless v.nil?
        @ttl || parent&.ttl || Familia.ttl
      end

    end

    def self.included base
      Familia.ld "[#{base}] Loaded #{self}"
      base.extend ClassMethods

      # Optionally define ttl in the class to make
      # sure we always have an array to work with.
      unless base.instance_variable_defined?(:@ttl)
        base.instance_variable_set(:@ttl, @ttl) # set above
      end
    end

    def ttl=(v)
      @ttl = v.to_f
    end

    def ttl
      @ttl || self.class.ttl
    end

    # Yo, check it out! We're gonna give our Redis data an expiration date!
    #
    # It's like slapping a "Best Before" sticker on your favorite snack,
    # but for data. How cool is that?
    #
    # @param ttl [Integer, nil] The Time To Live in seconds. Nil? No worries!
    #   We'll dig up the default from our secret stash.
    #
    # @return [Boolean] Did Redis pin that expiry note successfully?
    #   True for "Yep!", false for "Oops, butter fingers!"
    #
    # @example Teaching your pet rock the concept of mortality
    #   rocky.update_expiration(86400) # Dwayne gets to party in Redis for one whole day!
    #
    # @note If TTL is zero, your data gets a VIP pass to the Redis eternity club.
    #   Fancy, huh?
    #
    # @raise [Familia::Problem] If you try to feed it non-numbers or time-travel
    #   (negative numbers). It's strict, but fair!
    #
  def update_expiration(ttl = nil)
      ttl ||= self.ttl
      # It's important to raise exceptions here and not just log warnings. We
      # don't want to silently fail at setting expirations and cause data
      # retention issues (e.g. not removed in a timely fashion).
      #
      # For the same reason, we don't want to default to 0 bc there's not a
      # good reason for the ttl to not be set in the first place. If the
      # class doesn't have a ttl, the default comes from Familia.ttl (which
      # is 0).
      unless ttl.is_a?(Numeric)
        raise Familia::Problem, "TTL must be a number (#{ttl.class} in #{self.class})"
      end

      if ttl.zero?
        return Familia.ld "[update_expiration] No expiration for #{self.class} (#{rediskey})"
      end

      Familia.ld "[update_expiration] Expires #{rediskey} in #{ttl} seconds"

      # Redis' EXPIRE command returns 1 if the timeout was set, 0 if key does
      # not exist or the timeout could not be set. Via redis-rb here, it's
      # a bool.
      expire(ttl)
    end

    extend ClassMethods

    Familia::Base.add_feature self, :expiration
  end

end
