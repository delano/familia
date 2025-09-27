# lib/familia/features/relationships.rb

require 'securerandom'
require_relative 'relationships/score_encoding'
require_relative 'relationships/participation'
require_relative 'relationships/indexing'

module Familia
  module Features
    # Unified Relationships feature for Familia v2
    #
    # This feature merges the functionality of relatable_objects and relationships
    # into a single, Valkey/Redis-native implementation that embraces the "where does this appear?"
    # philosophy rather than "who owns this?".
    #
    # @example Basic usage
    #   class Domain < Familia::Horreum
    #
    #     identifier_field :domain_id
    #
    #     field :domain_id
    #     field :display_name
    #     field :created_at
    #     field :permission_bits
    #
    #     feature :relationships
    #
    #     # Multi-presence participation with score encoding
    #     participates_in Customer, :domains,
    #                     score: -> { permission_encode(created_at, permission_bits) }
    #     participates_in Team, :domains, score: :added_at
    #     participates_in Organization, :all_domains, score: :created_at
    #
    #     # O(1) lookups with Valkey/Redis hashes
    #     indexed_by :display_name, :domain_index, target: Customer
    #
    #     # Participation with bidirectional control (no method collisions)
    #     participates_in Customer, :domains
    #     participates_in Team, :domains, bidirectional: false
    #     participates_in Organization, :domains, type: :set
    #   end
    #
    # @example Generated methods (collision-free)
    #   # Participation methods
    #   Customer.domains                    # => Familia::SortedSet
    #   Customer.add_domain(domain, score)  # Add to customer's domains
    #   domain.in_customer_domains?(customer) # Check membership
    #
    #   # Indexing methods
    #   Customer.find_by_display_name(name) # O(1) lookup
    #
    #   # Bidirectional methods (collision-free naming)
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
        base.extend ModelClassMethods
        base.include ModelInstanceMethods

        # Include all relationship submodules and their class methods
        base.include ScoreEncoding

        base.include Participation
        base.extend Participation::ModelClassMethods

        base.include Indexing
        base.extend Indexing::ModelClassMethods
      end

      # Error classes
      class RelationshipError < StandardError; end
      class InvalidIdentifierError < RelationshipError; end
      class InvalidScoreError < RelationshipError; end
      class CascadeError < RelationshipError; end

      module ModelClassMethods
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

          configs[:participation] = participation_relationships if respond_to?(:participation_relationships)
          configs[:indexing] = indexing_relationships if respond_to?(:indexing_relationships)

          configs
        end

        # Validate relationship configurations
        def validate_relationships!
          errors = []

          # Check for method name collisions
          method_names = []

          if respond_to?(:participation_relationships)
            participation_relationships.each do |config|
              target_name = config[:target_class_name].downcase
              collection_name = config[:collection_name]

              method_names << "in_#{target_name}_#{collection_name}?"
              method_names << "add_to_#{target_name}_#{collection_name}"
              method_names << "remove_from_#{target_name}_#{collection_name}"
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

      module ModelInstanceMethods
        # NOTE: identifier and identifier= methods are provided by Horreum base class
        # No need to override them here - use the existing infrastructure

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

            # NOTE: Relationship-specific participation updates are done explicitly
            # since we need to know which specific collections this object should be in
          end

          result
        end

        # Override destroy to handle cascade operations
        def destroy!
          super
        end

        # Get comprehensive relationship status for this object
        def relationship_status
          status = {
            identifier: identifier,
            current_participations: [],
            index_memberships: [],
          }

          # Get participation memberships
          status[:current_participations] = current_participations if respond_to?(:current_participations)

          # Get index memberships
          status[:index_memberships] = indexing_memberships if respond_to?(:indexing_memberships)

          status
        end

        # Comprehensive cleanup - remove from all relationships
        def cleanup_all_relationships!
          # Remove from participation collections
          #
          # NOTE: This method has been removed for being poorly implemented. It
          # was repetative and laborious to debug. It'll come back in a cleaner
          # for after the rest of the module is in ship shape.
          #
          # remove_from_all_participations if respond_to?(:remove_from_all_participations)
          warn 'Not currently removing from participation collections. See pull #115.'

          # Remove from indexes
          remove_from_all_indexes if respond_to?(:remove_from_all_indexes)
        end

        # Dry run for relationship cleanup (preview what would be affected)
        def cleanup_preview
          preview = {
            participation_collections: [],
            index_entries: [],
          }

          preview
        end

        # Validate that this object's relationships are consistent
        def validate_relationships!
          errors = []

          # Validate identifier exists
          errors << 'Object identifier is nil' unless identifier

          # Validate participation memberships
          if respond_to?(:current_participations)
            current_participations.each do |membership|
              score = membership[:score]
              errors << "Invalid score in participation membership: #{membership}" if score && !score.is_a?(Numeric)
            end
          end

          raise RelationshipError, "Relationship validation failed for #{self}: #{errors.join('; ')}" if errors.any?

          true
        end

        # Refresh relationship data from Valkey/Redis (useful after external changes)
        def refresh_relationships!
          # Clear any cached relationship data
          @relationship_status = nil
          @current_participations = nil
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

        # Direct Valkey/Redis access for instance methods
        def dbclient
          self.class.dbclient
        end

        # Instance method wrapper for create_temp_key
        def create_temp_key(base_name, ttl = 300)
          timestamp = Familia.now.to_i
          random_suffix = SecureRandom.hex(3)
          temp_key = "temp:#{base_name}:#{timestamp}:#{random_suffix}"

          # UnsortedSet immediate expiry to ensure cleanup even if operation fails
          dbclient.expire(temp_key, ttl)

          temp_key
        end

        # Instance method wrapper for cleanup_temp_keys
        def cleanup_temp_keys(pattern = 'temp:*', batch_size = 100)
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

            break if cursor.zero?
          end
        end

        private

        # Find all Valkey/Redis keys related to this object
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
            dbclient.scan_each(match: pattern, count: 100) do |key|
              # Check if this key actually contains our object
              key_type = dbclient.type(key)

              case key_type
              when 'zset'
                related_keys << key if dbclient.zscore(key, id)
              when 'set'
                related_keys << key if dbclient.sismember(key, id)
              when 'list'
                related_keys << key if dbclient.lpos(key, id)
              when 'hash'
                # For hash keys, check if any field values match our identifier
                hash_values = dbclient.hvals(key)
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
