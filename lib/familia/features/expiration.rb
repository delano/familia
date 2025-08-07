# lib/familia/features/expiration.rb

module Familia
  module Features

    # Famnilia::Features::Expiration
    #
    module Expiration
      @default_expiration = nil

      # ClassMethods
      #
      module ClassMethods

        attr_writer :default_expiration

        def default_expiration(num = nil)
          @default_expiration = num.to_f unless num.nil?
          @default_expiration || parent&.default_expiration || Familia.default_expiration
        end

      end

      def self.included(base)
        Familia.ld "[#{base}] Loaded #{self}"
        base.extend ClassMethods

        # Optionally define default_expiration in the class to make
        # sure we always have an array to work with.
        unless base.instance_variable_defined?(:@default_expiration)
          base.instance_variable_set(:@default_expiration, @default_expiration) # set above
        end
      end

      def default_expiration=(num)
        @default_expiration = num.to_f
      end

      def default_expiration
        @default_expiration || self.class.default_expiration
      end

      # Sets an expiration time for the Database data associated with this object.
      #
      # This method allows setting a Time To Live (TTL) for the data in Redis,
      # after which it will be automatically removed.
      #
      # @param default_expiration [Integer, nil] The Time To Live in seconds. If nil, the default
      #   TTL will be used.
      #
      # @return [Boolean] Returns true if the expiration was set successfully,
      #   false otherwise.
      #
      # @example Setting an expiration of one day
      #   object.update_expiration(default_expiration: 86400)
      #
      # @note If Default expiration is set to zero, the expiration will be removed, making the
      #   data persist indefinitely.
      #
      # @raise [Familia::Problem] Raises an error if the default expiration is not a non-negative
      #   integer.
      #
      def update_expiration(default_expiration: nil)
        default_expiration ||= self.default_expiration

        if self.class.has_relations?
          Familia.ld "[update_expiration] #{self.class} has relations: #{self.class.related_fields.keys}"
          self.class.related_fields.each do |name, definition|
            next if definition.opts[:default_expiration].nil?

            obj = send(name)
            Familia.ld "[update_expiration] Updating expiration for #{name} (#{obj.dbkey}) to #{default_expiration}"
            obj.update_expiration(default_expiration: default_expiration)
          end
        end

        # It's important to raise exceptions here and not just log warnings. We
        # don't want to silently fail at setting expirations and cause data
        # retention issues (e.g. not removed in a timely fashion).
        #
        # For the same reason, we don't want to default to 0 bc there's not a
        # good reason for the default_expiration to not be set in the first place. If the
        # class doesn't have a default_expiration, the default comes from
        # Familia.default_expiration (which is 0, aka no-op/skip/do nothing).
        unless default_expiration.is_a?(Numeric)
          raise Familia::Problem, "Default expiration must be a number (#{default_expiration.class} in #{self.class})"
        end

        # If zero, simply skips setting an expiry for this key. If we were to set
        # 0 the database would drop the key immediately.
        if default_expiration.zero?
          return Familia.ld "[update_expiration] No expiration for #{self.class} (#{dbkey})"
        end

        Familia.ld "[update_expiration] Expires #{dbkey} in #{default_expiration} seconds"

        # Redis' EXPIRE command returns 1 if the timeout was set, 0 if key does
        # not exist or the timeout could not be set. Via redis-rb here, it's
        # a bool.
        expire(default_expiration)
      end

      Familia::Base.add_feature self, :expiration
    end

  end
end

module Familia
  # Add a default update_expiration method for all classes that include
  # Familia::Base. Since expiration is a core feature, we can confidently
  # call `horreum_instance.update_expiration` without defensive programming
  # even when expiration is not enabled for the horreum_instance class.
  module Base
    # Base implementation of update_expiration that maintains API compatibility
    # with the :expiration feature's implementation.
    #
    # This is a no-op implementation that gets overridden by features like
    # :expiration. It accepts an optional default_expiration parameter to maintain interface
    # compatibility with the overriding implementations.
    #
    # @param default_expiration [Integer, nil] Time To Live in seconds
    # @return [nil] Always returns nil
    #
    # @note This is a no-op implementation. Classes that need expiration
    #       functionality should include the :expiration feature.
    #
    def update_expiration(default_expiration: nil)
      Familia.ld <<~LOG
        [update_expiration] Feature not enabled for #{self.class}.
        Key: #{dbkey} Arg: #{default_expiration} (caller: #{caller(1..1)})
      LOG
      nil
    end
  end
end
