# lib/familia/features/expiration/extensions.rb

module Familia
  # Add a default update_expiration method for all classes that include
  # Familia::Base. Since expiration is a core feature, we can confidently
  # call `horreum_instance.update_expiration` without defensive programming
  # even when expiration is not enabled for the horreum_instance class.
  module Base
    # Base implementation of update_expiration that maintains API compatibility
    # with the :expiration feature's implementation.
    #
    # This is a no-op implementation that gets overridden by the :expiration
    # feature when it is enabled. This allows for calling this method on any
    # horreum model regardless of the feature status. It accepts an optional
    # expiration parameter to maintain interface compatibility with
    # the overriding implementations.
    #
    # @param expiration [Numeric, nil] Time To Live in seconds
    # @return [nil] Always returns nil for the base implementation
    #
    # @note This is a no-op implementation. Classes that need expiration
    #       functionality should include the :expiration feature.
    #
    # @example MyModel.new.update_expiration(expiration: 3600) # => nothing happens
    #
    def update_expiration(expiration: nil)
      Familia.ld <<~LOG
        [update_expiration] Expiration feature not enabled for #{self.class}.
        Key: #{dbkey} Arg: #{expiration} (caller: #{caller(1..1)})
      LOG
      nil
    end

    # Base implementation of ttl that returns -1 (no expiration set)
    #
    # @return [Integer] Always returns -1 for the base implementation
    #
    def ttl
      -1
    end

    # Base implementation of expires? that returns false
    #
    # @return [Boolean] Always returns false for the base implementation
    #
    def expires?
      false
    end

    # Base implementation of expired? that returns false
    #
    # @param _threshold [Numeric] Ignored in base implementation
    # @return [Boolean] Always returns false for the base implementation
    #
    def expired?(_threshold = 0)
      false
    end
  end
end
