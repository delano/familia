# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Methods that call load and dump (InstanceMethods)
    #
    # Note on refresh methods:
    # In this class, refresh! is the primary method that performs the Redis
    # query and state update. The non-bang refresh method is provided as a
    # convenience for method chaining, but still performs the same destructive
    # update as refresh!. This deviates from common Ruby conventions to better
    # fit the specific needs of this system.
    module Serialization
      #include Familia::RedisType::Serialization

      attr_writer :redis

      def redis
        @redis || self.class.redis
      end

      def transaction
        original_redis = self.redis

        begin
          redis.multi do |conn|
            self.instance_variable_set(:@redis, conn)
            yield(conn)
          end
        ensure
          self.redis = original_redis
        end
      end

      # A thin wrapper around `commit_fields` that updates the timestamps and
      # returns a boolean.
      def save
        Familia.trace :SAVE, redis, redisuri, caller(1..1) if Familia.debug?

        # Update timestamp fields
        self.updated = Familia.now.to_i
        self.created = Familia.now.to_i unless self.created

        # Thr return value of commit_fields is an array of strings: ["OK"].
        ret = commit_fields # e.g. ["OK"]

        Familia.ld "[save] #{self.class} #{rediskey} #{ret}"

        # Convert the return value to a boolean
        ret.all? { |value| value == "OK" }
      end

      # +return: [Array<String>] The return value of the Redis multi command
      def commit_fields
        Familia.ld "[commit_fields] #{self.class} #{rediskey} #{to_h}"
        transaction do |conn|
          hmset
          update_expiration
        end
      end

      def destroy!
        Familia.trace :DESTROY, redis, redisuri, caller(1..1) if Familia.debug?
        delete!
      end
      # Refreshes the object's state by querying Redis and overwriting the
      # current field values. This method performs a destructive update on the
      # object, regardless of unsaved changes.
      #
      # @note This is a destructive operation that will overwrite any unsaved
      #   changes.
      # @return The list of field names that were updated.
      def refresh!
        Familia.trace :REFRESH, redis, redisuri, caller(1..1) if Familia.debug?
        fields = hgetall
        Familia.ld "[refresh!] #{self.class} #{rediskey} #{fields}"
        optimistic_refresh(**fields)
      end

      # Refreshes the object's state and returns self to allow method chaining.
      # This method calls refresh! internally, performing the actual Redis
      # query and state update.
      #
      # @note While this method allows chaining, it still performs a
      #   destructive update like refresh!.
      # @return [self] Returns the object itself after refreshing, allowing
      #   method chaining.
      def refresh
        refresh!
        self
      end

      def to_h
        # Use self.class.fields to efficiently generate a hash
        # of all the fields for this object
        self.class.fields.inject({}) do |hsh, field|
          val = send(field)
          prepared = to_redis(val)
          Familia.ld " [to_h] field: #{field} val: #{val.class} prepared: #{prepared.class}"
          hsh[field] = prepared
          hsh
        end
      end

      def to_a
        self.class.fields.map do |field|
          val = send(field)
          prepared = to_redis(val)
          Familia.ld " [to_a] field: #{field} val: #{val.class} prepared: #{prepared.class}"
          prepared
        end
      end

      # The to_redis method in Familia::Redistype and Familia::Horreum serve
      # similar purposes but have some key differences in their implementation:
      #
      # Similarities:
      # - Both methods aim to serialize various data types for Redis storage
      # - Both handle basic data types like String, Symbol, and Numeric
      # - Both have provisions for custom serialization methods
      #
      # Differences:
      # - Familia::Redistype uses the opts[:class] for type hints
      # - Familia::Horreum had more explicit type checking and conversion
      # - Familia::Redistype includes more extensive debug tracing
      #
      # The centralized Familia.distinguisher method accommodates both approaches
      # by:
      # 1. Handling a wide range of data types, including those from both
      #    implementations
      # 2. Providing a 'strict_values' option for flexible type handling
      # 3. Supporting custom serialization through a dump_method
      # 4. Including debug tracing similar to Familia::Redistype
      #
      # By using Familia.distinguisher, we achieve more consistent behavior
      # across different parts of the library while maintaining the flexibility
      # to handle various data types and custom serialization needs. This
      # centralization also makes it easier to extend or modify serialization
      # behavior in the future.
      #
      def to_redis(val)
        prepared = Familia.distinguisher(val, false)

        if prepared.nil? && val.respond_to?(dump_method)
          prepared = val.send(dump_method)
        end

        if prepared.nil?
          Familia.ld "[#{self.class}#to_redis] nil returned for #{self.class}##{name}"
        end

        prepared
      end

      def update_expiration(ttl = nil)
        ttl ||= opts[:ttl]
        return if ttl.to_i.zero? # nil will be zero

        Familia.ld "#{rediskey} to #{ttl}"
        expire ttl.to_i
      end
    end
    # End of Serialization module

    include Serialization # these become Horreum instance methods
  end
end
