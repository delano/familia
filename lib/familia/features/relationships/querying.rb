# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      # Querying module for advanced Redis set operations on relationship collections
      # Provides union, intersection, difference operations with permission filtering
      module Querying
        # Class-level querying capabilities
        def self.included(base)
          base.extend ClassMethods
        end

        module ClassMethods
          # Union of multiple collections (accessible items across multiple sources)
          #
          # @param collections [Array<Hash>] Collection configurations
          # @param min_permission [Symbol] Minimum permission level
          # @param ttl [Integer] TTL for result set in seconds
          # @return [Familia::SortedSet] Temporary sorted set with results
          #
          # @example Union of accessible domains
          #   Domain.union_collections([
          #     { owner: customer, collection: :domains },
          #     { owner: team, collection: :domains },
          #     { owner: org, collection: :all_domains }
          #   ], min_permission: :read, ttl: 300)
          def union_collections(collections, min_permission: nil, ttl: 300, aggregate: :sum)
            return empty_result_set if collections.empty?

            temp_key = create_temp_key("union_#{name.downcase}", ttl)
            source_keys = build_collection_keys(collections)

            # Apply permission filtering if needed
            source_keys = filter_keys_by_permission(source_keys, min_permission, temp_key) if min_permission

            return empty_result_set if source_keys.empty?

            dbclient.zunionstore(temp_key, source_keys, aggregate: aggregate)
            dbclient.expire(temp_key, ttl)

            Familia::SortedSet.new(rediskey: temp_key, db: logical_database)
          end

          # Intersection of multiple collections (items present in ALL collections)
          #
          # @param collections [Array<Hash>] Collection configurations
          # @param min_permission [Symbol] Minimum permission level
          # @param ttl [Integer] TTL for result set in seconds
          # @return [Familia::SortedSet] Temporary sorted set with results
          def intersection_collections(collections, min_permission: nil, ttl: 300, aggregate: :sum)
            return empty_result_set if collections.empty?

            temp_key = create_temp_key("intersection_#{name.downcase}", ttl)
            source_keys = build_collection_keys(collections)

            # Apply permission filtering if needed
            source_keys = filter_keys_by_permission(source_keys, min_permission, temp_key) if min_permission

            return empty_result_set if source_keys.empty?

            dbclient.zinterstore(temp_key, source_keys, aggregate: aggregate)
            dbclient.expire(temp_key, ttl)

            Familia::SortedSet.new(rediskey: temp_key, db: logical_database)
          end

          # Difference of collections (items in first collection but not in others)
          #
          # @param base_collection [Hash] Base collection configuration
          # @param exclude_collections [Array<Hash>] Collections to exclude
          # @param min_permission [Symbol] Minimum permission level
          # @param ttl [Integer] TTL for result set in seconds
          # @return [Familia::SortedSet] Temporary sorted set with results
          def difference_collections(base_collection, exclude_collections = [], min_permission: nil, ttl: 300)
            temp_key = create_temp_key("difference_#{name.downcase}", ttl)

            base_key = build_collection_key(base_collection)
            exclude_keys = build_collection_keys(exclude_collections)

            # Apply permission filtering if needed
            if min_permission
              base_key = filter_key_by_permission(base_key, min_permission, "#{temp_key}_base")
              exclude_keys = filter_keys_by_permission(exclude_keys, min_permission, temp_key)
            end

            # Start with base collection
            dbclient.zunionstore(temp_key, [base_key])

            # Remove elements from exclude collections
            exclude_keys.each do |exclude_key|
              members_to_remove = dbclient.zrange(exclude_key, 0, -1)
              dbclient.zrem(temp_key, members_to_remove) if members_to_remove.any?
            end

            dbclient.expire(temp_key, ttl)

            Familia::SortedSet.new(rediskey: temp_key, db: logical_database)
          end

          # Find collections with shared members
          #
          # @param collections [Array<Hash>] Collection configurations
          # @param min_shared [Integer] Minimum number of shared members
          # @param ttl [Integer] TTL for result set in seconds
          # @return [Hash] Map of collection pairs to shared member counts
          def shared_members(collections, min_shared: 1, ttl: 300)
            return {} if collections.length < 2

            shared_results = {}
            collections.map { |c| build_collection_key(c) }

            # Compare each pair of collections
            collections.combination(2).each do |coll1, coll2|
              key1 = build_collection_key(coll1)
              key2 = build_collection_key(coll2)

              temp_key = create_temp_key("shared_#{SecureRandom.hex(4)}", ttl)

              # Use intersection to find shared members
              shared_count = dbclient.zinterstore(temp_key, [key1, key2])

              if shared_count >= min_shared
                shared_members_list = dbclient.zrange(temp_key, 0, -1, with_scores: true)
                shared_results["#{format_collection(coll1)} ∩ #{format_collection(coll2)}"] = {
                  count: shared_count,
                  members: shared_members_list
                }
              end

              dbclient.del(temp_key)
            end

            shared_results
          end

          # Query collections with complex filters
          #
          # @param collections [Array<Hash>] Collection configurations
          # @param filters [Hash] Query filters
          # @param ttl [Integer] TTL for result set in seconds
          # @return [Familia::SortedSet] Filtered result set
          #
          # @example Complex query
          #   Domain.query_collections([
          #     { owner: customer, collection: :domains },
          #     { owner: team, collection: :domains }
          #   ], {
          #     min_permission: :write,
          #     score_range: [1.week.ago.to_i, Time.now.to_i],
          #     limit: 50,
          #     operation: :union
          #   })
          def query_collections(collections, filters = {}, ttl: 300)
            return empty_result_set if collections.empty?

            operation = filters[:operation] || :union
            min_permission = filters[:min_permission]
            score_range = filters[:score_range]
            limit = filters[:limit]
            offset = filters[:offset] || 0

            temp_key = create_temp_key("query_#{name.downcase}", ttl)
            source_keys = build_collection_keys(collections)

            # Apply permission filtering
            source_keys = filter_keys_by_permission(source_keys, min_permission, temp_key) if min_permission

            return empty_result_set if source_keys.empty?

            # Perform set operation
            case operation
            when :union
              dbclient.zunionstore(temp_key, source_keys)
            when :intersection
              dbclient.zinterstore(temp_key, source_keys)
            end

            # Apply score range filtering
            if score_range
              min_score, max_score = score_range
              # Remove elements outside the score range
              dbclient.zremrangebyscore(temp_key, '-inf', "(#{min_score}")
              dbclient.zremrangebyscore(temp_key, "(#{max_score}", '+inf')
            end

            # Apply limit
            if limit
              total_count = dbclient.zcard(temp_key)
              if total_count > offset + limit
                # Keep only the requested range
                dbclient.zremrangebyrank(temp_key, offset + limit, -1)
              end
              dbclient.zremrangebyrank(temp_key, 0, offset - 1) if offset > 0
            end

            dbclient.expire(temp_key, ttl)

            Familia::SortedSet.new(rediskey: temp_key, db: logical_database)
          end

          # Get collection statistics
          #
          # @param collections [Array<Hash>] Collection configurations
          # @return [Hash] Statistics about the collections
          def collection_statistics(collections)
            stats = {
              total_collections: collections.length,
              collection_sizes: {},
              total_unique_members: 0,
              total_members: 0,
              score_ranges: {}
            }

            all_members = Set.new

            collections.each do |collection|
              key = build_collection_key(collection)
              collection_name = format_collection(collection)

              size = dbclient.zcard(key)
              stats[:collection_sizes][collection_name] = size
              stats[:total_members] += size

              next unless size > 0

              # Get score range
              min_score = dbclient.zrange(key, 0, 0, with_scores: true).first&.last
              max_score = dbclient.zrange(key, -1, -1, with_scores: true).first&.last

              stats[:score_ranges][collection_name] = {
                min: min_score,
                max: max_score,
                min_decoded: min_score ? decode_score(min_score) : nil,
                max_decoded: max_score ? decode_score(max_score) : nil
              }

              # Track unique members
              members = dbclient.zrange(key, 0, -1)
              all_members.merge(members)
            end

            stats[:total_unique_members] = all_members.size
            stats[:overlap_ratio] = if stats[:total_members] > 0
                                      (stats[:total_members] - stats[:total_unique_members]).to_f / stats[:total_members]
                                    else
                                      0
                                    end

            stats
          end

          private

          # Build Redis key for a collection
          def build_collection_key(collection)
            if collection[:owner]
              owner = collection[:owner]
              collection_name = collection[:collection]
              "#{owner.class.name.downcase}:#{owner.identifier}:#{collection_name}"
            elsif collection[:key]
              collection[:key]
            else
              raise ArgumentError, 'Collection must have :owner and :collection or :key'
            end
          end

          # Build Redis keys for multiple collections
          def build_collection_keys(collections)
            collections.map { |collection| build_collection_key(collection) }
          end

          # Filter collections by permission level
          def filter_keys_by_permission(keys, min_permission, temp_prefix)
            return keys unless min_permission

            permission_value = ScoreEncoding.permission_level_value(min_permission)
            filtered_keys = []

            keys.each_with_index do |key, index|
              filtered_key = "#{temp_prefix}_filtered_#{index}"

              # Copy elements with sufficient permission
              min_score = encode_score(0, permission_value)
              dbclient.zunionstore(filtered_key, [key])
              dbclient.zremrangebyscore(filtered_key, '-inf', "(#{min_score}")

              if dbclient.zcard(filtered_key) > 0
                filtered_keys << filtered_key
                dbclient.expire(filtered_key, 300) # Temporary key cleanup
              else
                dbclient.del(filtered_key)
              end
            end

            filtered_keys
          end

          # Filter single key by permission
          def filter_key_by_permission(key, min_permission, temp_key)
            return key unless min_permission

            permission_value = ScoreEncoding.permission_level_value(min_permission)
            min_score = encode_score(0, permission_value)

            dbclient.zunionstore(temp_key, [key])
            dbclient.zremrangebyscore(temp_key, '-inf', "(#{min_score}")
            dbclient.expire(temp_key, 300)

            temp_key
          end

          # Format collection for display
          def format_collection(collection)
            if collection[:owner]
              owner = collection[:owner]
              "#{owner.class.name}:#{owner.identifier}:#{collection[:collection]}"
            elsif collection[:key]
              collection[:key]
            else
              collection.to_s
            end
          end

          # Create empty result set
          def empty_result_set
            temp_key = create_temp_key("empty_#{name.downcase}", 60)
            # Create an actual empty zset
            dbclient.zadd(temp_key, 0, "__nil__")
            dbclient.zrem(temp_key, "__nil__")
            dbclient.expire(temp_key, 60)
            Familia::SortedSet.new(rediskey: temp_key, db: logical_database)
          end
        end

        # Instance methods for querying relationships
        module InstanceMethods
          # Find all collections this object appears in with specific permissions
          #
          # @param min_permission [Symbol] Minimum permission level
          # @return [Array<Hash>] Collections this object is a member of
          def accessible_collections(min_permission: nil)
            collections = []

            # Check tracking relationships
            if self.class.respond_to?(:tracking_relationships)
              collections.concat(find_tracking_collections(min_permission))
            end

            # Check membership relationships
            if self.class.respond_to?(:membership_relationships)
              collections.concat(find_membership_collections(min_permission))
            end

            collections
          end

          # Get permission level in a specific collection
          #
          # @param owner [Object] Collection owner
          # @param collection_name [Symbol] Collection name
          # @return [Symbol, nil] Permission level or nil if not a member
          def permission_in_collection(owner, collection_name)
            collection_key = "#{owner.class.name.downcase}:#{owner.identifier}:#{collection_name}"
            score = dbclient.zscore(collection_key, identifier)

            return nil unless score

            decoded = permission_decode(score)
            decoded[:permission]
          end

          # Check if this object has specific permission in a collection
          #
          # @param owner [Object] Collection owner
          # @param collection_name [Symbol] Collection name
          # @param required_permission [Symbol] Required permission level
          # @return [Boolean] True if object has required permission
          def has_permission_in_collection?(owner, collection_name, required_permission)
            current_permission = permission_in_collection(owner, collection_name)
            return false unless current_permission

            current_level = ScoreEncoding::PERMISSION_LEVELS[current_permission] || 0
            required_level = ScoreEncoding::PERMISSION_LEVELS[required_permission] || 0

            current_level >= required_level
          end

          # Find similar objects based on shared collection membership
          #
          # @param min_shared_collections [Integer] Minimum shared collections
          # @param ttl [Integer] TTL for temporary keys
          # @return [Array<Hash>] Similar objects with similarity scores
          def find_similar_objects(min_shared_collections: 1, ttl: 300)
            my_collections = accessible_collections
            return [] if my_collections.empty?

            similar_objects = {}

            my_collections.each do |collection_info|
              collection_key = collection_info[:key]

              # Get all members of this collection
              other_members = dbclient.zrange(collection_key, 0, -1)
              other_members.delete(identifier) # Remove self

              other_members.each do |other_identifier|
                similar_objects[other_identifier] ||= {
                  shared_collections: 0,
                  collections: [],
                  identifier: other_identifier
                }
                similar_objects[other_identifier][:shared_collections] += 1
                similar_objects[other_identifier][:collections] << collection_info
              end
            end

            # Filter by minimum shared collections and calculate similarity
            similar_objects.values
                           .select { |obj| obj[:shared_collections] >= min_shared_collections }
                           .map do |obj|
              obj[:similarity] = obj[:shared_collections].to_f / my_collections.length
              obj
            end
              .sort_by { |obj| -obj[:similarity] }
          end

          private

          # Find tracking collections this object is in
          def find_tracking_collections(min_permission)
            collections = []

            self.class.tracking_relationships.each do |config|
              context_class_name = config[:context_class_name]
              collection_name = config[:collection_name]

              pattern = "#{context_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                score = dbclient.zscore(key, identifier)
                next unless score

                # Check permission if required
                if min_permission
                  decoded = permission_decode(score)
                  required_level = ScoreEncoding::PERMISSION_LEVELS[min_permission] || 0
                  actual_level = ScoreEncoding::PERMISSION_LEVELS[decoded[:permission]] || 0
                  next if actual_level < required_level
                end

                context_id = key.split(':')[1]
                collections << {
                  type: :tracking,
                  context_class: context_class_name,
                  context_id: context_id,
                  collection_name: collection_name,
                  key: key,
                  score: score,
                  permission: permission_decode(score)[:permission]
                }
              end
            end

            collections
          end

          # Find membership collections this object is in
          def find_membership_collections(min_permission)
            collections = []

            self.class.membership_relationships.each do |config|
              owner_class_name = config[:owner_class_name]
              collection_name = config[:collection_name]
              type = config[:type]

              pattern = "#{owner_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                is_member = false
                score = nil

                case type
                when :sorted_set
                  score = dbclient.zscore(key, identifier)
                  is_member = !score.nil?
                when :set
                  is_member = dbclient.sismember(key, identifier)
                when :list
                  is_member = dbclient.lpos(key, identifier) != nil
                end

                next unless is_member

                # Check permission for sorted sets
                if min_permission && type == :sorted_set && score
                  decoded = permission_decode(score)
                  required_level = ScoreEncoding::PERMISSION_LEVELS[min_permission] || 0
                  actual_level = ScoreEncoding::PERMISSION_LEVELS[decoded[:permission]] || 0
                  next if actual_level < required_level
                end

                owner_id = key.split(':')[1]
                collection_info = {
                  type: :membership,
                  owner_class: owner_class_name,
                  owner_id: owner_id,
                  collection_name: collection_name,
                  collection_type: type,
                  key: key
                }

                if score
                  collection_info[:score] = score
                  collection_info[:permission] = permission_decode(score)[:permission]
                end

                collections << collection_info
              end
            end

            collections
          end
        end

        # Include instance methods when this module is included
        def self.included(base)
          base.include InstanceMethods
          super
        end
      end
    end
  end
end
