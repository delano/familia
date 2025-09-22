# lib/familia/features/relationships.rb

require 'securerandom'
require_relative 'relationships/score_encoding'
require_relative 'relationships/database_operations'
require_relative 'relationships/tracking'
require_relative 'relationships/indexing'
require_relative 'relationships/membership'
require_relative 'relationships/cascading'
require_relative 'relationships/querying'
require_relative 'relationships/permission_management'

module Familia
  module Features
    # Unified Relationships feature for Familia v2
    #
    # This feature merges the functionality of relatable_objects and relationships
    # into a single, Redis-native implementation that embraces the "where does this appear?"
    # philosophy rather than "who owns this?".
    #
    # Key improvements in v2:
    # - Multi-presence: Objects can exist in multiple collections simultaneously
    # - Score encoding: Metadata embedded in Redis scores for efficiency
    # - Collision-free: Method names include collection names to prevent conflicts
    # - Redis-native: All operations use Redis commands, no Ruby iteration
    # - Atomic operations: Multi-collection updates happen atomically
    #
    # Breaking changes from v1:
    # - Single feature: Use `feature :relationships` instead of separate features
    # - Simplified identifier: Use `identifier :field` instead of `identifier_field :field`
    # - No ownership concept: Remove `owned_by`, use multi-presence instead
    # - Method naming: Generated methods include collection names for uniqueness
    # - Score encoding: Scores can carry metadata like permissions
    #
    # @example Basic usage
    #   class Domain < Familia::Horreum
    #     feature :relationships
    #
    #     identifier :domain_id
    #     field :domain_id
    #     field :display_name
    #     field :created_at
    #     field :permission_bits
    #
    #     # Multi-presence tracking with score encoding
    #     tracked_in Customer, :domains,
    #                score: -> { permission_encode(created_at, permission_bits) }
    #     tracked_in Team, :domains, score: :added_at
    #     tracked_in Organization, :all_domains, score: :created_at
    #
    #     # O(1) lookups with Redis hashes
    #     indexed_by :display_name, :domain_index, context: Customer
    #     indexed_by :display_name, :global_domain_index, context: :global
    #
    #     # Context-aware membership (no method collisions)
    #     member_of Customer, :domains
    #     member_of Team, :domains
    #     member_of Organization, :domains
    #   end
    #
    # @example Generated methods (collision-free)
    #   # Tracking methods
    #   Customer.domains                    # => Familia::SortedSet
    #   Customer.add_domain(domain, score)  # Add to customer's domains
    #   domain.in_customer_domains?(customer) # Check membership
    #
    #   # Indexing methods
    #   Customer.find_by_display_name(name) # O(1) lookup
    #   Domain.find_by_display_name(name) # Global lookup
    #
    #   # Membership methods (collision-free naming)
    #   domain.add_to_customer_domains(customer)  # Specific collection
    #   domain.add_to_team_domains(team)          # Different collection
    #   domain.in_customer_domains?(customer)     # Check specific membership
    #
    # @example Score encoding for permissions
    #   # Encode permission in score
    #   score = domain.permission_encode(Familia.now, :write)
    #   # => 1704067200.004 (timestamp + permission bits)
    #
    #   # Decode permission from score
    #   decoded = domain.permission_decode(score)
    #   # => { timestamp: 1704067200, permissions: 4, permission_list: [:write] }
    #
    #   # Query with permission filtering
    #   Customer.domains_with_permission(:read)
    #
    # @example Multi-collection operations
    #   # Atomic updates across multiple collections
    #   domain.update_multiple_presence([
    #     { key: "customer:123:domains", score: current_score },
    #     { key: "team:456:domains", score: permission_encode(Familia.now, :read) }
    #   ], :add, domain.identifier)
    #
    #   # UnsortedSet operations on collections
    #   accessible = Domain.union_collections([
    #     { owner: customer, collection: :domains },
    #     { owner: team, collection: :domains }
    #   ], min_permission: :read)
    module Relationships
      # Register the feature with Familia
      Familia::Base.add_feature Relationships, :relationships

      # Feature initialization
      def self.included(base)
        Familia.ld "[#{base}] Relationships included"
        base.extend ClassMethods
        base.include InstanceMethods

        # Include all relationship submodules and their class methods
        base.include ScoreEncoding
        base.include DatabaseOperations

        base.include Tracking
        base.extend Tracking::ClassMethods

        base.include Indexing
        base.extend Indexing::ClassMethods

        base.include Membership
        base.extend Membership::ClassMethods

        base.include Cascading
        base.extend Cascading::ClassMethods

        base.include Querying
        base.extend Querying::ClassMethods
      end

      # Error classes
      class RelationshipError < StandardError; end
      class InvalidIdentifierError < RelationshipError; end
      class InvalidScoreError < RelationshipError; end
      class CascadeError < RelationshipError; end

      module ClassMethods
        # Define the identifier for this class (replaces identifier_field)
        # This is a compatibility wrapper around the existing identifier_field method
        #
        # @param field [Symbol] The field to use as identifier
        # @return [Symbol] The identifier field
        #
        # @example
        #   identifier :domain_id
        def identifier(field = nil)
          return identifier_field(field) if field

          identifier_field
        end

        # Generate a secure temporary identifier
        def generate_identifier
          SecureRandom.hex(8)
        end

        # Get all relationship configurations for this class
        def relationship_configs
          configs = {}

          configs[:tracking] = tracking_relationships if respond_to?(:tracking_relationships)
          configs[:indexing] = indexing_relationships if respond_to?(:indexing_relationships)
          configs[:membership] = membership_relationships if respond_to?(:membership_relationships)

          configs
        end

        # Validate relationship configurations
        def validate_relationships!
          errors = []

          # Check for method name collisions
          method_names = []

          if respond_to?(:tracking_relationships)
            tracking_relationships.each do |config|
              context_name = config[:context_class_name].downcase
              collection_name = config[:collection_name]

              method_names << "in_#{context_name}_#{collection_name}?"
              method_names << "add_to_#{context_name}_#{collection_name}"
              method_names << "remove_from_#{context_name}_#{collection_name}"
            end
          end

          if respond_to?(:membership_relationships)
            membership_relationships.each do |config|
              owner_name = config[:owner_class_name].downcase
              collection_name = config[:collection_name]

              method_names << "in_#{owner_name}_#{collection_name}?"
              method_names << "add_to_#{owner_name}_#{collection_name}"
              method_names << "remove_from_#{owner_name}_#{collection_name}"
            end
          end

          # Check for duplicates
          duplicates = method_names.group_by(&:itself).select { |_, v| v.size > 1 }.keys
          errors << "Method name collisions detected: #{duplicates.join(', ')}" if duplicates.any?

          # Validate identifier field exists
          id_field = identifier
          unless instance_methods.include?(id_field) || method_defined?(id_field)
            errors << "Identifier field '#{id_field}' is not defined"
          end

          raise RelationshipError, "Relationship validation failed: #{errors.join('; ')}" if errors.any?

          true
        end

        # Create a new instance with relationships initialized
        def create_with_relationships(attributes = {})
          instance = new(attributes)
          instance.initialize_relationships
          instance
        end

        # Class method wrapper for create_temp_key
        def create_temp_key(base_name, ttl = 300)
          timestamp = Familia.now.to_i
          random_suffix = SecureRandom.hex(3)
          temp_key = "temp:#{base_name}:#{timestamp}:#{random_suffix}"

          # UnsortedSet immediate expiry to ensure cleanup even if operation fails
          if respond_to?(:dbclient)
            dbclient.expire(temp_key, ttl)
          else
            Familia.dbclient.expire(temp_key, ttl)
          end

          temp_key
        end

        # Include core score encoding methods at class level
        include ScoreEncoding

        private

        # Simple constantize method to convert string to constant
        def constantize_class_name(class_name)
          class_name.split('::').reduce(Object) { |mod, name| mod.const_get(name) }
        rescue NameError
          # If the class doesn't exist, return nil
          nil
        end
      end

      module InstanceMethods
        # Get the identifier value for this instance
        # Uses the existing Horreum identifier infrastructure
        def identifier
          id_field = self.class.identifier_field
          send(id_field) if respond_to?(id_field)
        end

        # UnsortedSet the identifier value for this instance
        def identifier=(value)
          id_field = self.class.identifier_field
          send("#{id_field}=", value) if respond_to?("#{id_field}=")
        end

        # Initialize relationships (called after object creation)
        def initialize_relationships
          # This can be overridden by subclasses to set up initial relationships
        end

        # Override save to update relationships automatically
        def save(update_expiration: true)
          result = super

          if result
            # Automatically update all indexes when object is saved
            update_all_indexes if respond_to?(:update_all_indexes)

            # Auto-add to class-level tracking collections
            add_to_class_tracking_collections if respond_to?(:add_to_class_tracking_collections)

            # NOTE: Relationship-specific membership and tracking updates are done explicitly
            # since we need to know which specific collections this object should be in
          end

          result
        end

        # Override destroy to handle cascade operations
        def destroy!
          # Execute cascade operations before destroying the object
          execute_cascade_operations if respond_to?(:execute_cascade_operations)

          super
        end

        # Get comprehensive relationship status for this object
        def relationship_status
          status = {
            identifier: identifier,
            tracking_memberships: [],
            membership_collections: [],
            index_memberships: [],
          }

          # Get tracking memberships
          if respond_to?(:tracking_collections_membership)
            status[:tracking_memberships] = tracking_collections_membership
          end

          # Get membership collections
          status[:membership_collections] = membership_collections if respond_to?(:membership_collections)

          # Get index memberships
          status[:index_memberships] = indexing_memberships if respond_to?(:indexing_memberships)

          status
        end

        # Comprehensive cleanup - remove from all relationships
        def cleanup_all_relationships!
          # Remove from tracking collections
          remove_from_all_tracking_collections if respond_to?(:remove_from_all_tracking_collections)

          # Remove from membership collections
          remove_from_all_memberships if respond_to?(:remove_from_all_memberships)

          # Remove from indexes
          remove_from_all_indexes if respond_to?(:remove_from_all_indexes)
        end

        # Dry run for relationship cleanup (preview what would be affected)
        def cleanup_preview
          preview = {
            tracking_collections: [],
            membership_collections: [],
            index_entries: [],
          }

          if respond_to?(:cascade_dry_run)
            cascade_preview = cascade_dry_run
            preview.merge!(cascade_preview)
          end

          preview
        end

        # Validate that this object's relationships are consistent
        def validate_relationships!
          errors = []

          # Validate identifier exists
          errors << 'Object identifier is nil' unless identifier

          # Validate tracking memberships
          if respond_to?(:tracking_collections_membership)
            tracking_collections_membership.each do |membership|
              score = membership[:score]
              errors << "Invalid score in tracking membership: #{membership}" if score && !score.is_a?(Numeric)
            end
          end

          raise RelationshipError, "Relationship validation failed for #{self}: #{errors.join('; ')}" if errors.any?

          true
        end

        # Refresh relationship data from Redis (useful after external changes)
        def refresh_relationships!
          # Clear any cached relationship data
          @relationship_status = nil
          @tracking_memberships = nil
          @membership_collections = nil
          @index_memberships = nil

          # Reload fresh data
          relationship_status
        end

        # Create a snapshot of current relationship state (for debugging)
        def relationship_snapshot
          {
            timestamp: Familia.now,
            identifier: identifier,
            class: self.class.name,
            status: relationship_status,
            dbkeys: find_related_dbkeys,
          }
        end

        # Direct Redis access for instance methods
        def redis
          self.class.dbclient
        end

        # Instance method wrapper for create_temp_key
        def create_temp_key(base_name, ttl = 300)
          timestamp = Familia.now.to_i
          random_suffix = SecureRandom.hex(3)
          temp_key = "temp:#{base_name}:#{timestamp}:#{random_suffix}"

          # UnsortedSet immediate expiry to ensure cleanup even if operation fails
          redis.expire(temp_key, ttl)

          temp_key
        end

        # Instance method wrapper for cleanup_temp_keys
        def cleanup_temp_keys(pattern = 'temp:*', batch_size = 100)
          cursor = 0

          loop do
            cursor, keys = redis.scan(cursor, match: pattern, count: batch_size)

            if keys.any?
              # Check TTL and remove keys that should have expired
              keys.each_slice(batch_size) do |key_batch|
                redis.pipelined do |pipeline|
                  key_batch.each do |key|
                    ttl = redis.ttl(key)
                    pipeline.del(key) if ttl == -1 # Key exists but has no TTL
                  end
                end
              end
            end

            break if cursor.zero?
          end
        end

        private

        # Find all Redis keys related to this object
        def find_related_dbkeys
          related_keys = []
          id = identifier
          return related_keys unless id

          # Scan for keys that might contain this object
          patterns = [
            '*:*:*', # General pattern for relationship keys
            "*#{id}*", # Keys containing the identifier
          ]

          patterns.each do |pattern|
            redis.scan_each(match: pattern, count: 100) do |key|
              # Check if this key actually contains our object
              key_type = redis.type(key)

              case key_type
              when 'zset'
                related_keys << key if redis.zscore(key, id)
              when 'set'
                related_keys << key if redis.sismember(key, id)
              when 'list'
                related_keys << key if redis.lpos(key, id)
              when 'hash'
                # For hash keys, check if any field values match our identifier
                hash_values = redis.hvals(key)
                related_keys << key if hash_values.include?(id.to_s)
              end
            end
          end

          related_keys.uniq
        end
      end
    end
  end
end
