# lib/familia/features/expiration.rb
#
# frozen_string_literal: true

require_relative 'expiration/extensions'

module Familia
  module Features
    # Expiration is a feature that provides Time To Live (TTL) management for Familia
    # objects and their associated Valkey/Redis data structures. It enables automatic
    # data cleanup and supports cascading expiration across related objects.
    #
    # This feature allows you to:
    # - UnsortedSet default expiration times at the class level
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
    #   # UnsortedSet custom expiration for new objects
    #   session.update_expiration(expiration: 2.hours)
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
    # expiration feature cascades TTL to all related structures during
    # +update_expiration+ (which is called automatically by +save+). Each
    # relation receives either its own +default_expiration+ or the parent
    # value as a fallback. Relations with +no_expiration: true+ are
    # excluded from cascade entirely.
    #
    #   class User < Familia::Horreum
    #     feature :expiration
    #     default_expiration 30.days
    #
    #     field :email, :name
    #     list :sessions        # Inherits parent TTL (30 days) via cascade
    #     set :permissions      # Inherits parent TTL (30 days) via cascade
    #     hashkey :preferences  # Inherits parent TTL (30 days) via cascade
    #   end
    #
    # Note: cascade applies EXPIRE to the relation's key, so the key must
    # already exist in the database. Relations populated after +save+ will
    # receive TTL from their own write methods (if they have
    # +default_expiration+) or from a subsequent +update_expiration+ call.
    #
    # Fine-Grained Control:
    #
    # Related structures can have their own expiration settings, or opt out
    # of expiration cascade entirely:
    #
    #   class Analytics < Familia::Horreum
    #     feature :expiration
    #     default_expiration 1.year
    #
    #     field :metric_name
    #     list :hourly_data, default_expiration: 1.week    # Own TTL (1 week)
    #     list :daily_data, default_expiration: 1.month    # Own TTL (1 month)
    #     list :monthly_data                               # Inherits class TTL (1 year) via cascade
    #     hashkey :permanent_config, no_expiration: true   # Excluded from cascade
    #   end
    #
    # Zero Expiration:
    #
    # Setting expiration to 0 (zero) disables TTL, making data persist indefinitely:
    #
    #   session.update_expiration(expiration: 0)  # No expiration
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
    #         update_expiration(expiration)
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
    #   session.update_expiration(expiration: "invalid")
    #   # => Familia::Problem: Default expiration must be a number
    #
    #   session.update_expiration(expiration: -1)
    #   # => Familia::Problem: Default expiration must be non-negative
    #
    # Performance Considerations:
    #
    # - TTL operations are performed on Valkey/Redis side with minimal overhead
    # - Cascading expiration uses pipelining for efficiency when possible
    # - Zero expiration values skip Valkey/Redis EXPIRE calls entirely
    # - TTL queries are direct db operations (very fast)
    #
    module Expiration
      @default_expiration = nil

      Familia::Base.add_feature self, :expiration

      using Familia::Refinements::TimeLiterals

      def self.included(base)
        Familia.trace :LOADED, self, base if Familia.debug?
        base.extend ModelClassMethods

        # Initialize default_expiration instance variable if not already defined
        # This ensures the class has a place to store its default expiration setting
        return if base.instance_variable_defined?(:@default_expiration)

        # The instance var here will return the value from the implementing
        # model class (or nil if it's not set, as you'd expect).
        base.instance_variable_set(:@default_expiration, @default_expiration)
      end

      # Familia::Expiration::ModelClassMethods
      #
      module ModelClassMethods
        # UnsortedSet the default expiration time for instances of this class
        #
        # @param value [Numeric] Time in seconds (can be fractional)
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
        # @example UnsortedSet default expiration
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

      # UnsortedSet the default expiration time for this instance
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

      # Sets an expiration time for the Valkey/Redis data associated with this object
      #
      # This method allows setting a Time To Live (TTL) for the data in Valkey/Redis,
      # after which it will be automatically removed. The method also handles
      # cascading expiration to related data structures when applicable.
      #
      # @param expiration [Numeric, nil] The Time To Live in seconds. If nil,
      #   the default TTL will be used.
      #
      # @return [Boolean] Returns true if the expiration was set successfully,
      #   false otherwise.
      #
      # @example Setting an expiration of one day
      #   object.update_expiration(expiration: 86400)
      #
      # @example Using default expiration
      #   object.update_expiration  # Uses class default_expiration
      #
      # @example Removing expiration (persist indefinitely)
      #   object.update_expiration(expiration: 0)
      #
      # @note If default expiration is set to zero, the expiration will be removed,
      #   making the data persist indefinitely.
      #
      # @raise [Familia::Problem] Raises an error if the default expiration is not
      #   a non-negative number.
      #
      def update_expiration(expiration: nil)
        expiration ||= default_expiration

        # Handle cascading expiration to related data structures.
        #
        # By default, all relations inherit the parent object's expiration.
        # Relations with an explicit `default_expiration:` option use that
        # value instead. Relations with `no_expiration: true` are excluded
        # from cascade entirely and persist independently.
        if self.class.relations?
          Familia.debug "[update_expiration] #{self.class} has relations: #{self.class.related_fields.keys}"
          self.class.related_fields.each do |name, definition|
            # Skip relations explicitly excluded from expiration cascade
            next if definition.opts[:no_expiration]

            # Use the relation's own default_expiration when defined,
            # falling back to the parent expiration value. This allows
            # per-relation TTL (e.g. list :hourly_data, default_expiration: 1.week)
            # to take precedence over the class-level default_expiration.
            rel_expiration = definition.opts[:default_expiration] || expiration

            obj = send(name)
            Familia.debug "[update_expiration] Updating expiration for #{name} (#{obj.dbkey}) to #{rel_expiration}"
            obj.update_expiration(expiration: rel_expiration)
          end
        end

        # Validate expiration value
        # It's important to raise exceptions here and not just log warnings. We
        # don't want to silently fail at setting expirations and cause data
        # retention issues (e.g. not removed in a timely fashion).
        unless expiration.is_a?(Numeric)
          raise Familia::Problem,
                "Default expiration must be a number (#{expiration.class} given for #{self.class})"
        end

        unless expiration >= 0
          raise Familia::Problem,
                "Default expiration must be non-negative (#{expiration} given for #{self.class})"
        end

        # If zero, simply skip setting an expiry for this key. If we were to set
        # 0, Valkey/Redis would drop the key immediately.
        if expiration.zero?
          Familia.debug "[update_expiration] No expiration for #{self.class} (#{dbkey})"
          return true
        end

        # Structured TTL operation logging
        Familia.debug "TTL updated",
          operation: :expire,
          key: dbkey,
          ttl_seconds: expiration,
          class: self.class.name,
          identifier: (identifier rescue nil)

        # The Valkey/Redis' EXPIRE command returns 1 if the timeout was set, 0
        # if key does not exist or the timeout could not be set. Via redis-rb,
        # it's a boolean.
        expire(expiration)
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
        dbclient.ttl(dbkey)
      end

      # Check if this object's data will expire
      #
      # @return [Boolean] true if TTL is set, false if data persists indefinitely
      #
      def expires?
        ttl.positive?
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
        return false if current_ttl == -1 # no expiration set
        return true  if current_ttl == -2 # key does not exist

        current_ttl <= threshold
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
        return false unless current_ttl.positive? # no current expiration set

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
        dbclient.persist(dbkey)
      end

      # Returns a report of TTL values for the main key and all relation keys.
      #
      # This is useful for detecting TTL drift where the main hash has a TTL
      # but one or more relation keys do not (or vice versa). Queries all
      # keys using pipelined TTL calls for efficiency.
      #
      # @return [Hash] A hash with :main and :relations keys
      #   - :main [Hash] { key: String, ttl: Integer }
      #   - :relations [Hash{Symbol => Hash}] Each relation name maps to
      #     { key: String, ttl: Integer }
      #
      # TTL values follow Redis conventions:
      #   - Positive integer: seconds remaining
      #   - -1: key exists but has no expiration
      #   - -2: key does not exist
      #
      # @example Inspect TTL across all keys
      #   session.ttl_report
      #   # => {
      #   #      main: { key: "session:abc123:object", ttl: 3599 },
      #   #      relations: {
      #   #        sessions: { key: "session:abc123:sessions", ttl: -1 },
      #   #        tags:     { key: "session:abc123:tags", ttl: 3598 }
      #   #      }
      #   #    }
      #
      # @example Detect TTL drift
      #   report = user.ttl_report
      #   drifted = report[:relations].select { |_, v| v[:ttl] == -1 }
      #   warn "TTL drift detected: #{drifted.keys}" if drifted.any?
      #
      def ttl_report
        report = {
          main: { key: dbkey, ttl: dbclient.ttl(dbkey) },
          relations: {},
        }

        return report unless self.class.relations?

        self.class.related_fields.each_key do |name|
          obj = send(name)
          report[:relations][name] = {
            key: obj.dbkey,
            ttl: dbclient.ttl(obj.dbkey),
          }
        end

        report
      end
    end
  end
end
