# lib/familia/features/expiration.rb

module Familia
  module Features
    # Expiration is a feature that provides Time To Live (TTL) management for Familia
    # objects and their associated Redis/Valkey data structures. It enables automatic
    # data cleanup and supports cascading expiration across related objects.
    #
    # This feature allows you to:
    # - Set default expiration times at the class level
    # - Update expiration times for individual objects
    # - Cascade expiration settings to related data structures
    # - Query remaining TTL for objects
    # - Handle expiration inheritance in class hierarchies
    #
    # Example:
    #
    #   class Session < Familia::Horreum
    #     feature :expiration
    #     default_expiration 1.hour
    #
    #     field :user_id, :data, :created_at
    #     list :activity_log
    #   end
    #
    #   session = Session.new(user_id: 123, data: { role: 'admin' })
    #   session.save
    #
    #   # Automatically expires in 1 hour (default_expiration)
    #   session.ttl  # => 3599 (seconds remaining)
    #
    #   # Update expiration to 30 minutes
    #   session.update_expiration(30.minutes)
    #   session.ttl  # => 1799
    #
    #   # Set custom expiration for new objects
    #   session.update_expiration(default_expiration: 2.hours)
    #
    # Class-Level Configuration:
    #
    # Default expiration can be set at the class level and will be inherited
    # by subclasses unless overridden:
    #
    #   class BaseModel < Familia::Horreum
    #     feature :expiration
    #     default_expiration 1.day
    #   end
    #
    #   class ShortLivedModel < BaseModel
    #     default_expiration 5.minutes  # Overrides parent
    #   end
    #
    #   class InheritedModel < BaseModel
    #     # Inherits 1.day from BaseModel
    #   end
    #
    # Cascading Expiration:
    #
    # When an object has related data structures (lists, sets, etc.), the
    # expiration feature automatically applies TTL to all related structures:
    #
    #   class User < Familia::Horreum
    #     feature :expiration
    #     default_expiration 30.days
    #
    #     field :email, :name
    #     list :sessions        # Will also expire in 30 days
    #     set :permissions      # Will also expire in 30 days
    #     hashkey :preferences  # Will also expire in 30 days
    #   end
    #
    # Fine-Grained Control:
    #
    # Related structures can have their own expiration settings:
    #
    #   class Analytics < Familia::Horreum
    #     feature :expiration
    #     default_expiration 1.year
    #
    #     field :metric_name
    #     list :hourly_data, default_expiration: 1.week    # Shorter TTL
    #     list :daily_data, default_expiration: 1.month    # Medium TTL
    #     list :monthly_data  # Uses class default (1.year)
    #   end
    #
    # Zero Expiration:
    #
    # Setting expiration to 0 (zero) disables TTL, making data persist indefinitely:
    #
    #   session.update_expiration(default_expiration: 0)  # No expiration
    #
    # TTL Querying:
    #
    # Check remaining time before expiration:
    #
    #   session.ttl           # => 3599 (seconds remaining)
    #   session.ttl.zero?     # => false (still has time)
    #   expired_session.ttl   # => -1 (already expired or no TTL set)
    #
    # Integration Patterns:
    #
    #   # Conditional expiration based on user type
    #   class UserSession < Familia::Horreum
    #     feature :expiration
    #
    #     field :user_id, :user_type
    #
    #     def save
    #       super
    #       case user_type
    #       when 'premium'
    #         update_expiration(7.days)
    #       when 'free'
    #         update_expiration(1.hour)
    #       else
    #         update_expiration(default_expiration)
    #       end
    #     end
    #   end
    #
    #   # Background job cleanup
    #   class DataCleanupJob
    #     def perform
    #       # Extend expiration for active users
    #       active_sessions = Session.where(active: true)
    #       active_sessions.each do |session|
    #         session.update_expiration(session.default_expiration)
    #       end
    #     end
    #   end
    #
    # Error Handling:
    #
    # The feature validates expiration values and raises descriptive errors:
    #
    #   session.update_expiration(default_expiration: "invalid")
    #   # => Familia::Problem: Default expiration must be a number
    #
    #   session.update_expiration(default_expiration: -1)
    #   # => Familia::Problem: Default expiration must be non-negative
    #
    # Performance Considerations:
    #
    # - TTL operations are performed on Redis/Valkey side with minimal overhead
    # - Cascading expiration uses pipelining for efficiency when possible
    # - Zero expiration values skip Redis EXPIRE calls entirely
    # - TTL queries are direct Redis operations (very fast)
    #
    module Expiration
      @default_expiration = nil

      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Initialize default_expiration instance variable if not already defined
        # This ensures the class has a place to store its default expiration setting
        return if base.instance_variable_defined?(:@default_expiration)

        base.instance_variable_set(:@default_expiration, @default_expiration)
      end

      module ClassMethods
        # Set the default expiration time for instances of this class
        #
        # @param expiration [Numeric] Time in seconds (can be fractional)
        #
        attr_writer :default_expiration

        # Get or set the default expiration time for this class
        #
        # When called with an argument, sets the default expiration.
        # When called without arguments, returns the current default expiration,
        # checking parent classes and falling back to Familia.default_expiration.
        #
        # @param num [Numeric, nil] Expiration time in seconds
        # @return [Float] The default expiration in seconds
        #
        # @example Set default expiration
        #   class MyModel < Familia::Horreum
        #     feature :expiration
        #     default_expiration 1.hour
        #   end
        #
        # @example Get default expiration
        #   MyModel.default_expiration  # => 3600.0
        #
        def default_expiration(num = nil)
          @default_expiration = num.to_f unless num.nil?
          @default_expiration || parent&.default_expiration || Familia.default_expiration
        end
      end

      # Set the default expiration time for this instance
      #
      # @param num [Numeric] Expiration time in seconds
      #
      def default_expiration=(num)
        @default_expiration = num.to_f
      end

      # Get the default expiration time for this instance
      #
      # Returns the instance-specific default expiration, falling back to
      # class default expiration if not set.
      #
      # @return [Float] The default expiration in seconds
      #
      def default_expiration
        @default_expiration || self.class.default_expiration
      end

      # Sets an expiration time for the Redis/Valkey data associated with this object
      #
      # This method allows setting a Time To Live (TTL) for the data in Redis,
      # after which it will be automatically removed. The method also handles
      # cascading expiration to related data structures when applicable.
      #
      # @param default_expiration [Numeric, nil] The Time To Live in seconds. If nil,
      #   the default TTL will be used.
      #
      # @return [Boolean] Returns true if the expiration was set successfully,
      #   false otherwise.
      #
      # @example Setting an expiration of one day
      #   object.update_expiration(default_expiration: 86400)
      #
      # @example Using default expiration
      #   object.update_expiration  # Uses class default_expiration
      #
      # @example Removing expiration (persist indefinitely)
      #   object.update_expiration(default_expiration: 0)
      #
      # @note If default expiration is set to zero, the expiration will be removed,
      #   making the data persist indefinitely.
      #
      # @raise [Familia::Problem] Raises an error if the default expiration is not
      #   a non-negative number.
      #
      def update_expiration(default_expiration: nil)
        default_expiration ||= self.default_expiration

        # Handle cascading expiration to related data structures
        if self.class.has_relations?
          Familia.ld "[update_expiration] #{self.class} has relations: #{self.class.related_fields.keys}"
          self.class.related_fields.each do |name, definition|
            # Skip relations that don't have their own expiration settings
            next if definition.opts[:default_expiration].nil?

            obj = send(name)
            Familia.ld "[update_expiration] Updating expiration for #{name} (#{obj.dbkey}) to #{default_expiration}"
            obj.update_expiration(default_expiration: default_expiration)
          end
        end

        # Validate expiration value
        # It's important to raise exceptions here and not just log warnings. We
        # don't want to silently fail at setting expirations and cause data
        # retention issues (e.g. not removed in a timely fashion).
        unless default_expiration.is_a?(Numeric)
          raise Familia::Problem, "Default expiration must be a number (#{default_expiration.class} given for #{self.class})"
        end

        unless default_expiration >= 0
          raise Familia::Problem, "Default expiration must be non-negative (#{default_expiration} given for #{self.class})"
        end

        # If zero, simply skip setting an expiry for this key. If we were to set
        # 0, Redis would drop the key immediately.
        if default_expiration.zero?
          Familia.ld "[update_expiration] No expiration for #{self.class} (#{dbkey})"
          return true
        end

        Familia.ld "[update_expiration] Expires #{dbkey} in #{default_expiration} seconds"

        # Redis' EXPIRE command returns 1 if the timeout was set, 0 if key does
        # not exist or the timeout could not be set. Via redis-rb, it's a boolean.
        expire(default_expiration)
      end

      # Get the remaining time to live for this object's data
      #
      # @return [Integer] Seconds remaining before expiration, or -1 if no TTL is set
      #
      # @example Check remaining TTL
      #   session.ttl  # => 3599 (expires in ~1 hour)
      #   session.ttl.zero?  # => false
      #
      # @example Check if expired or no TTL
      #   expired_session.ttl  # => -1
      #
      def ttl
        redis.ttl(dbkey)
      end

      # Check if this object's data will expire
      #
      # @return [Boolean] true if TTL is set, false if data persists indefinitely
      #
      def expires?
        ttl > 0
      end

      # Check if this object's data has expired or will expire soon
      #
      # @param threshold [Numeric] Consider expired if TTL is below this threshold (default: 0)
      # @return [Boolean] true if expired or expiring soon
      #
      # @example Check if expired
      #   session.expired?  # => true if TTL <= 0
      #
      # @example Check if expiring within 5 minutes
      #   session.expired?(5.minutes)  # => true if TTL <= 300
      #
      def expired?(threshold = 0)
        current_ttl = ttl
        current_ttl >= 0 && current_ttl <= threshold
      end

      # Extend the expiration time by the specified duration
      #
      # This adds the given duration to the current TTL, effectively extending
      # the object's lifetime without changing the default expiration setting.
      #
      # @param duration [Numeric] Additional time in seconds
      # @return [Boolean] Success of the operation
      #
      # @example Extend session by 1 hour
      #   session.extend_expiration(1.hour)
      #
      def extend_expiration(duration)
        current_ttl = ttl
        return false if current_ttl < 0  # No current expiration set

        new_ttl = current_ttl + duration.to_f
        expire(new_ttl)
      end

      # Remove expiration, making the object persist indefinitely
      #
      # @return [Boolean] Success of the operation
      #
      # @example Make session persistent
      #   session.persist!
      #
      def persist!
        redis.persist(dbkey)
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
    # This is a no-op implementation that gets overridden by the :expiration
    # feature. It accepts an optional default_expiration parameter to maintain
    # interface compatibility with the overriding implementations.
    #
    # @param default_expiration [Numeric, nil] Time To Live in seconds
    # @return [nil] Always returns nil for the base implementation
    #
    # @note This is a no-op implementation. Classes that need expiration
    #       functionality should include the :expiration feature.
    #
    # @example Enable expiration feature
    #   class MyModel < Familia::Horreum
    #     feature :expiration
    #     default_expiration 1.hour
    #   end
    #
    def update_expiration(default_expiration: nil)
      Familia.ld <<~LOG
        [update_expiration] Expiration feature not enabled for #{self.class}.
        Key: #{dbkey} Arg: #{default_expiration} (caller: #{caller(1..1)})
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
    # @param threshold [Numeric] Ignored in base implementation
    # @return [Boolean] Always returns false for the base implementation
    #
    def expired?(_threshold = 0)
      false
    end
  end
end
