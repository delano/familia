# lib/familia/features/expiration.rb


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

    # Sets an expiration time for the Redis data associated with this object.
    #
    # This method allows setting a Time To Live (TTL) for the data in Redis,
    # after which it will be automatically removed.
    #
    # @param ttl [Integer, nil] The Time To Live in seconds. If nil, the default
    #   TTL will be used.
    #
    # @return [Boolean] Returns true if the expiration was set successfully,
    #   false otherwise.
    #
    # @example Setting an expiration of one day
    #   object.update_expiration(ttl: 86400)
    #
    # @note If TTL is set to zero, the expiration will be removed, making the
    #   data persist indefinitely.
    #
    # @raise [Familia::Problem] Raises an error if the TTL is not a non-negative
    #   integer.
    #
    def update_expiration(ttl: nil)
      ttl ||= self.ttl

      if self.class.has_relations?
        Familia.ld "[update_expiration] #{self.class} has relations: #{self.class.redis_types.keys}"
        self.class.redis_types.each do |name, definition|
          next if definition.opts[:ttl].nil?
          obj = send(name)
          Familia.ld "[update_expiration] Updating expiration for #{name} (#{obj.rediskey}) to #{ttl}"
          obj.update_expiration(ttl: ttl)
        end
      end

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
