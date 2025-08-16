# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      # Redis operations module providing atomic multi-collection operations
      # and native Redis set operations for relationships
      module RedisOperations
        # Execute multiple Redis operations atomically using MULTI/EXEC
        #
        # @param redis [Redis] Redis connection to use
        # @yield [Redis] Yields Redis connection in transaction context
        # @return [Array] Results from Redis transaction
        #
        # @example Atomic multi-collection update
        #   atomic_operation(redis) do |tx|
        #     tx.zadd("customer:123:domains", score, domain_id)
        #     tx.zadd("team:456:domains", score, domain_id)
        #     tx.hset("domain_index", domain_name, domain_id)
        #   end
        def atomic_operation(redis = nil)
          redis ||= self.class.dbclient

          dbclient.multi do |tx|
            yield tx if block_given?
          end
        end

        # Update object presence in multiple collections atomically
        #
        # @param collections [Array<Hash>] Array of collection configurations
        # @param action [Symbol] Action to perform (:add, :remove)
        # @param identifier [String] Object identifier
        # @param default_score [Float] Default score if not specified per collection
        #
        # @example Update presence in multiple collections
        #   update_multiple_presence([
        #     { key: "customer:123:domains", score: current_score },
        #     { key: "team:456:domains", score: permission_encode(Time.now, :read) },
        #     { key: "org:789:all_domains", score: current_score }
        #   ], :add, domain.identifier)
        def update_multiple_presence(collections, action, identifier, default_score = nil)
          return unless collections&.any?

          redis = self.class.dbclient

          atomic_operation(redis) do |tx|
            collections.each do |collection_config|
              redis_key = collection_config[:key]
              score = collection_config[:score] || default_score || current_score

              case action
              when :add
                tx.zadd(redis_key, score, identifier)
              when :remove
                tx.zrem(redis_key, identifier)
              when :update
                # Use ZADD with XX flag to only update existing members
                tx.zadd(redis_key, score, identifier, xx: true)
              end
            end
          end
        end

        # Perform Redis set operations (union, intersection, difference) on sorted sets
        #
        # @param operation [Symbol] Operation type (:union, :intersection, :difference)
        # @param destination [String] Redis key for result storage
        # @param source_keys [Array<String>] Source Redis keys to operate on
        # @param weights [Array<Float>] Optional weights for union operations
        # @param aggregate [Symbol] Aggregation method (:sum, :min, :max)
        # @param ttl [Integer] TTL for destination key in seconds
        # @return [Integer] Number of elements in resulting set
        #
        # @example Union of accessible domains
        #   set_operation(:union, "temp:accessible_domains:#{user_id}",
        #                 ["customer:domains", "team:domains", "org:domains"],
        #                 ttl: 300)
        def set_operation(operation, destination, source_keys, weights: nil, aggregate: :sum, ttl: nil)
          return 0 if source_keys.empty?

          redis = self.class.dbclient
          0

          atomic_operation(redis) do |tx|
            case operation
            when :union
              if weights
                tx.zunionstore(destination, source_keys.zip(weights).to_h, aggregate: aggregate)
              else
                tx.zunionstore(destination, source_keys, aggregate: aggregate)
              end
            when :intersection
              if weights
                tx.zinterstore(destination, source_keys.zip(weights).to_h, aggregate: aggregate)
              else
                tx.zinterstore(destination, source_keys, aggregate: aggregate)
              end
            when :difference
              # Redis doesn't have ZDIFFSTORE until Redis 6.2, so we simulate it
              # First copy the first set, then remove elements from other sets
              first_key = source_keys.first
              other_keys = source_keys[1..]

              tx.zunionstore(destination, [first_key])
              other_keys.each do |key|
                # Get members of this set and remove them from destination
                members = dbclient.zrange(key, 0, -1)
                tx.zrem(destination, members) if members.any?
              end
            end

            tx.expire(destination, ttl) if ttl
          end

          # Get final count (this is approximate for the transaction)
          dbclient.zcard(destination)
        end

        # Create temporary Redis key with automatic cleanup
        #
        # @param base_name [String] Base name for the temporary key
        # @param ttl [Integer] TTL in seconds (default: 300)
        # @return [String] Generated temporary key name
        #
        # @example
        #   temp_key = create_temp_key("user_accessible_domains", 600)
        #   #=> "temp:user_accessible_domains:1704067200:abc123"
        def create_temp_key(base_name, ttl = 300)
          timestamp = Time.now.to_i
          random_suffix = SecureRandom.hex(3)
          temp_key = "temp:#{base_name}:#{timestamp}:#{random_suffix}"

          # Set immediate expiry to ensure cleanup even if operation fails
          redis_connection.expire(temp_key, ttl)

          temp_key
        end

        # Batch add multiple items to a sorted set
        #
        # @param redis_key [String] Redis sorted set key
        # @param items [Array<Hash>] Array of {member: String, score: Float} hashes
        # @param mode [Symbol] Add mode (:normal, :nx, :xx, :lt, :gt)
        #
        # @example Batch add domains with scores
        #   batch_zadd("customer:domains", [
        #     { member: "domain1", score: encode_score(Time.now, permission: :read) },
        #     { member: "domain2", score: encode_score(Time.now, permission: :write) }
        #   ])
        def batch_zadd(redis_key, items, mode: :normal)
          return 0 if items.empty?

          self.class.dbclient

          # Convert to format expected by Redis ZADD
          zadd_args = items.flat_map { |item| [item[:score], item[:member]] }

          case mode
          when :nx
            dbclient.zadd(redis_key, zadd_args, nx: true)
          when :xx
            dbclient.zadd(redis_key, zadd_args, xx: true)
          when :lt
            dbclient.zadd(redis_key, zadd_args, lt: true)
          when :gt
            dbclient.zadd(redis_key, zadd_args, gt: true)
          else
            dbclient.zadd(redis_key, zadd_args)
          end
        end

        # Query sorted set with score filtering and permission checking
        #
        # @param redis_key [String] Redis sorted set key
        # @param start_score [Float] Minimum score (inclusive)
        # @param end_score [Float] Maximum score (inclusive)
        # @param offset [Integer] Offset for pagination
        # @param count [Integer] Maximum number of results
        # @param with_scores [Boolean] Include scores in results
        # @param min_permission [Symbol] Minimum permission level required
        # @return [Array] Query results
        #
        # @example Query domains with read permission or higher
        #   query_by_score("customer:domains",
        #                  encode_score(1.hour.ago, 0),
        #                  encode_score(Time.now, MAX_METADATA),
        #                  min_permission: :read)
        def query_by_score(redis_key, start_score = '-inf', end_score = '+inf',
                           offset: 0, count: -1, with_scores: false, min_permission: nil)
          self.class.dbclient

          # Adjust score range for permission filtering
          if min_permission
            permission_value = ScoreEncoding.permission_level_value(min_permission)
            # Ensure minimum score includes required permission level
            if start_score.is_a?(Numeric)
              decoded = decode_score(start_score)
              start_score = encode_score(decoded[:timestamp], permission_value) if decoded[:metadata] < permission_value
            else
              start_score = encode_score(0, permission_value)
            end
          end

          options = {
            limit: (count > 0 ? [offset, count] : nil),
            with_scores: with_scores
          }.compact

          results = dbclient.zrangebyscore(redis_key, start_score, end_score, **options)

          # Filter results by permission if needed (double-check for precision issues)
          if min_permission && with_scores
            permission_value = ScoreEncoding.permission_level_value(min_permission)
            results = results.select do |_member, score|
              decoded = decode_score(score)
              decoded[:metadata] >= permission_value
            end
          end

          results
        end

        # Clean up expired temporary keys
        #
        # @param pattern [String] Pattern to match temporary keys
        # @param batch_size [Integer] Number of keys to process at once
        #
        # @example Clean up old temporary keys
        #   cleanup_temp_keys("temp:user_*", 100)
        def cleanup_temp_keys(pattern = 'temp:*', batch_size = 100)
          self.class.dbclient
          cursor = 0

          loop do
            cursor, keys = dbclient.scan(cursor, match: pattern, count: batch_size)

            if keys.any?
              # Check TTL and remove keys that should have expired
              keys.each_slice(batch_size) do |key_batch|
                dbclient.pipelined do |pipeline|
                  key_batch.each do |key|
                    ttl = dbclient.ttl(key)
                    pipeline.del(key) if ttl == -1 # Key exists but has no TTL
                  end
                end
              end
            end

            break if cursor == 0
          end
        end

        # Get Redis connection for the current class or instance
        def redis_connection
          if self.class.respond_to?(:dbclient)
            self.class.dbclient
          elsif respond_to?(:dbclient)
            dbclient
          else
            Familia.dbclient
          end
        end

        private

        # Validate Redis key format
        def validate_redis_key(key)
          raise ArgumentError, 'Redis key cannot be nil or empty' if key.nil? || key.empty?
          raise ArgumentError, 'Redis key must be a string' unless key.is_a?(String)

          key
        end
      end
    end
  end
end
