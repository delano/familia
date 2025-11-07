# lib/familia/features/relationships/participation/target_methods.rb

require_relative '../collection_operations'

module Familia
  module Features
    module Relationships
      # Methods added to TARGET classes (the ones specified in participates_in)
      # These methods allow target instances to manage their collections of participants
      #
      # Example: When Domain calls `participates_in Customer, :domains`
      # Customer instances get methods to manage their domains collection
      module TargetMethods
        using Familia::Refinements::StylizeWords
        extend CollectionOperations

        # Visual Guide for methods added to TARGET instances:
        # ====================================================
        # When Domain calls: participates_in Customer, :domains
        #
        # Customer instances (TARGET) get these methods:
        # ├── domains                           # Get the domains collection
        # ├── add_domain(domain, score)        # Add a domain to my collection
        # ├── remove_domain(domain)            # Remove a domain from my collection
        # ├── add_domains([...])               # Bulk add domains
        # └── domains_with_permission(level)   # Query with score filtering (sorted_set only)

        module Builder
          extend CollectionOperations

          # Build all target methods for a participation relationship
          # @param target_class [Class] The class receiving these methods (e.g., Customer)
          # @param collection_name [Symbol] Name of the collection (e.g., :domains)
          # @param type [Symbol] Collection type (:sorted_set, :set, :list)
          def self.build(target_class, collection_name, type)
            # FIRST: Ensure the DataType field is defined on the target class
            TargetMethods::Builder.ensure_collection_field(target_class, collection_name, type)

            # Core target methods
            build_collection_getter(target_class, collection_name, type)
            build_add_item(target_class, collection_name, type)
            build_remove_item(target_class, collection_name, type)
            build_bulk_add(target_class, collection_name, type)

            # Type-specific methods
            return unless type == :sorted_set

            build_permission_query(target_class, collection_name)
          end

          # Build class-level collection methods (for class_participates_in)
          # @param target_class [Class] The class receiving these methods
          # @param collection_name [Symbol] Name of the collection
          # @param type [Symbol] Collection type
          def self.build_class_level(target_class, collection_name, type)
            # FIRST: Ensure the class-level DataType field is defined
            target_class.send("class_#{type}", collection_name)

            # Class-level collection getter (e.g., User.all_users)
            build_class_collection_getter(target_class, collection_name, type)
            build_class_add_method(target_class, collection_name, type)
            build_class_remove_method(target_class, collection_name)
          end

          # Build method to get the collection
          # Creates: customer.domains
          def self.build_collection_getter(target_class, collection_name, type)
            # No need to define the method - Horreum automatically creates it
            # when we call ensure_collection_field above. This method is
            # kept for backwards compatibility but now does nothing.
            # The field definition (sorted_set :domains) creates the accessor automatically.
          end

          # Build method to add an item to the collection
          # Creates: customer.add_domains_instance(domain, score)
          def self.build_add_item(target_class, collection_name, type)
            method_name = "add_#{collection_name}_instance"

            target_class.define_method(method_name) do |item, score = nil|
              collection = send(collection_name)

              # Calculate score if needed and not provided
              if type == :sorted_set && score.nil? && item.respond_to?(:calculate_participation_score)
                score = item.calculate_participation_score(self.class, collection_name)
              end

              # Use transaction for atomicity between collection add and reverse index tracking
              # All operations use Horreum's DataType methods (not direct Redis calls)
              transaction do |_tx|
                # Add to collection using DataType method (ZADD/SADD/RPUSH)
                TargetMethods::Builder.add_to_collection(
                  collection,
                  item,
                  score: score,
                  type: type,
                  target_class: self.class,
                  collection_name: collection_name,
                )

                # Track participation in reverse index using DataType method (SADD)
                item.track_participation_in(collection.dbkey) if item.respond_to?(:track_participation_in)
              end
            end
          end

          # Build method to remove an item from the collection
          # Creates: customer.remove_domains_instance(domain)
          def self.build_remove_item(target_class, collection_name, type)
            method_name = "remove_#{collection_name}_instance"

            target_class.define_method(method_name) do |item|
              collection = send(collection_name)

              # Use transaction for atomicity between collection remove and reverse index untracking
              # All operations use Horreum's DataType methods (not direct Redis calls)
              transaction do |_tx|
                # Remove from collection using DataType method (ZREM/SREM/LREM)
                TargetMethods::Builder.remove_from_collection(collection, item, type: type)

                # Remove from participation tracking using DataType method (SREM)
                item.untrack_participation_in(collection.dbkey) if item.respond_to?(:untrack_participation_in)
              end
            end
          end

          # Build method for bulk adding items
          # Creates: customer.add_domains([domain1, domain2, ...])
          def self.build_bulk_add(target_class, collection_name, type)
            method_name = "add_#{collection_name}"

            target_class.define_method(method_name) do |items|
              return if items.empty?

              collection = send(collection_name)

              # Use transaction for atomicity across all bulk additions and reverse index tracking
              # All operations use Horreum's DataType methods (not direct Redis calls)
              transaction do |_tx|
                # Bulk add to collection using DataType methods (multiple ZADD/SADD/RPUSH)
                TargetMethods::Builder.bulk_add_to_collection(collection, items, type: type, target_class: self.class,
collection_name: collection_name)

                # Track all participations using DataType methods (multiple SADD)
                items.each do |item|
                  item.track_participation_in(collection.dbkey) if item.respond_to?(:track_participation_in)
                end
              end
            end
          end

          # Build permission query for sorted sets
          # Creates: customer.domains_with_permission(min_level)
          def self.build_permission_query(target_class, collection_name)
            method_name = "#{collection_name}_with_permission"

            target_class.define_method(method_name) do |min_permission = :read|
              collection = send(collection_name)

              # Assumes ScoreEncoding module is available
              if defined?(ScoreEncoding)
                permission_score = ScoreEncoding.permission_encode(0, min_permission)
                collection.zrangebyscore(permission_score, '+inf', with_scores: true)
              else
                # Fallback to all members if ScoreEncoding not available
                collection.members(with_scores: true)
              end
            end
          end

          # Build class-level collection getter
          # Creates: User.all_users (class method)
          def self.build_class_collection_getter(target_class, collection_name, type)
            # No need to define the method - Horreum automatically creates it
            # when we call class_#{type} above. This method is kept for
            # backwards compatibility but now does nothing.
            # The field definition (class_sorted_set :all_users) creates the accessor automatically.
          end

          # Build class-level add method
          # Creates: User.add_to_all_users(user, score)
          def self.build_class_add_method(target_class, collection_name, type)
            method_name = "add_to_#{collection_name}"

            target_class.define_singleton_method(method_name) do |item, score = nil|
              collection = send(collection_name.to_s)

              # Calculate score if needed
              if type == :sorted_set && score.nil?
                score = if item.respond_to?(:calculate_participation_score)
                  item.calculate_participation_score('class', collection_name)
                elsif item.respond_to?(:current_score)
                  item.current_score
                else
                  Familia.now.to_f
                end
              end

              TargetMethods::Builder.add_to_collection(
                collection,
                item,
                score: score,
                type: type,
                target_class: self.class,
                collection_name: collection_name,
              )
            end
          end

          # Build class-level remove method
          # Creates: User.remove_from_all_users(user)
          def self.build_class_remove_method(target_class, collection_name)
            method_name = "remove_from_#{collection_name}"

            target_class.define_singleton_method(method_name) do |item|
              collection = send(collection_name.to_s)
              TargetMethods::Builder.remove_from_collection(collection, item)
            end
          end
        end
      end
    end
  end
end
