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
        Familia.debug "[#{base}] Relationships included"
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

        # Class method wrapper for create_temp_key
        def create_temp_key(base_name, ttl = 300)
          timestamp = Familia.now.to_i
          random_suffix = SecureRandom.hex(3)
          temp_key = Familia.join('temp', base_name, timestamp, random_suffix)

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
      end

      module ModelInstanceMethods
        # NOTE: identifier and identifier= methods are provided by Horreum base class
        # No need to override them here - use the existing infrastructure

        # Override save to update relationships automatically
        def save(update_expiration: true)
          result = super

          if result && respond_to?(:update_all_indexes)
            # Automatically update all indexes when object is saved
            update_all_indexes

            # NOTE: Relationship-specific participation updates are done explicitly
            # since we need to know which specific collections this object should be in
          end

          result
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
          status[:index_memberships] = current_indexings if respond_to?(:current_indexings)

          status
        end

        # Comprehensive cleanup - remove from all relationships
        #
        # @deprecated This method is poorly implemented and will be removed in v3.0.
        #   The participation collection removal logic was repetitive and difficult to debug.
        #   A cleaner implementation will be provided in a future version.
        #   See pull #115 for details.
        #
        # @note Currently only removes from indexes, not participation collections
        def cleanup_all_relationships!
          warn '[DEPRECATED] cleanup_all_relationships! will be removed in v3.0. See pull #115.'
          warn 'Not currently removing from participation collections. Only indexes will be cleaned.'

          # Remove from indexes
          remove_from_all_indexes if respond_to?(:remove_from_all_indexes)
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

        # Direct Valkey/Redis access for instance methods
        def dbclient
          self.class.dbclient
        end

        # Instance method wrapper for create_temp_key
        def create_temp_key(base_name, ttl = 300)
          timestamp = Familia.now.to_i
          random_suffix = SecureRandom.hex(3)
          temp_key = Familia.join('temp', base_name, timestamp, random_suffix)

          # UnsortedSet immediate expiry to ensure cleanup even if operation fails
          dbclient.expire(temp_key, ttl)

          temp_key
        end

        private
      end
    end
  end
end
