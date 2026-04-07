# lib/familia/features/relationships/participation/target_methods.rb
#
# frozen_string_literal: true

require_relative '../collection_operations'
require_relative 'through_model_operations'
require_relative 'staged_operations'

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

          # Include ThroughModelOperations for through model lifecycle
          extend Participation::ThroughModelOperations

          # Build all target methods for a participation relationship
          # @param target_class [Class] The class receiving these methods (e.g., Customer)
          # @param collection_name [Symbol] Name of the collection (e.g., :domains)
          # @param type [Symbol] Collection type (:sorted_set, :set, :list)
          # @param through [Symbol, Class, nil] Through model class for join table pattern
          # @param staged [Symbol, nil] Staging set name for deferred activation
          def self.build(target_class, collection_name, type, through = nil, staged = nil)
            # FIRST: Ensure the DataType field is defined on the target class
            TargetMethods::Builder.ensure_collection_field(target_class, collection_name, type)

            # Create staging set if staged: option provided
            TargetMethods::Builder.ensure_collection_field(target_class, staged, :sorted_set) if staged

            # Core target methods
            build_collection_getter(target_class, collection_name, type)
            build_add_item(target_class, collection_name, type, through)
            build_remove_item(target_class, collection_name, type, through)
            build_bulk_add(target_class, collection_name, type)

            # Staged relationship methods (requires through model)
            if staged && through
              build_stage_method(target_class, collection_name, staged, through)
              build_activate_method(target_class, collection_name, staged, through)
              build_unstage_method(target_class, collection_name, staged, through)
              build_bulk_stage_method(target_class, collection_name, staged, through)
              build_bulk_unstage_method(target_class, collection_name, staged, through)
            end

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
          # Creates: customer.add_domains_instance(domain, score, through_attrs: {})
          def self.build_add_item(target_class, collection_name, type, through = nil)
            method_name = "add_#{collection_name}_instance"

            target_class.define_method(method_name) do |item, score = nil, through_attrs: {}|
              collection = send(collection_name)

              # Calculate score if needed and not provided
              if type == :sorted_set && score.nil? && item.respond_to?(:calculate_participation_score)
                score = item.calculate_participation_score(self.class, collection_name)
              end

              # Resolve through class if specified
              through_class = through ? Familia.resolve_class(through) : nil

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

              # TRANSACTION BOUNDARY: Through model operations intentionally happen AFTER
              # the transaction block closes. This is a deliberate design decision because:
              #
              # 1. ThroughModelOperations.find_or_create performs load operations that would
              #    return Redis::Future objects inside a transaction, breaking the flow
              # 2. The core participation (collection add + tracking) is atomic within the tx
              # 3. Through model creation is logically separate - if it fails, the participation
              #    itself succeeded and can be cleaned up or retried independently
              #
              # If Familia's transaction handling changes in the future, revisit this boundary.
              through_model = if through_class
                Participation::ThroughModelOperations.find_or_create(
                  through_class: through_class,
                  target: self,
                  participant: item,
                  attrs: through_attrs,
                )
              end

              # Return through model if using :through, otherwise self for backward compat
              through_model || self
            end
          end

          # Build method to remove an item from the collection
          # Creates: customer.remove_domains_instance(domain)
          def self.build_remove_item(target_class, collection_name, type, through = nil)
            method_name = "remove_#{collection_name}_instance"

            target_class.define_method(method_name) do |item|
              collection = send(collection_name)

              # Resolve through class if specified
              through_class = through ? Familia.resolve_class(through) : nil

              # Use transaction for atomicity between collection remove and reverse index untracking
              # All operations use Horreum's DataType methods (not direct Redis calls)
              transaction do |_tx|
                # Remove from collection using DataType method (ZREM/SREM/LREM)
                TargetMethods::Builder.remove_from_collection(collection, item, type: type)

                # Remove from participation tracking using DataType method (SREM)
                item.untrack_participation_in(collection.dbkey) if item.respond_to?(:untrack_participation_in)
              end

              # TRANSACTION BOUNDARY: Through model destruction intentionally happens AFTER
              # the transaction block. See build_add_item for detailed rationale.
              # The core removal is atomic; through model cleanup is a separate operation.
              return unless through_class

              Participation::ThroughModelOperations.find_and_destroy(
                through_class: through_class,
                target: self,
                participant: item,
              )
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

          # Build method to stage a through model for deferred activation
          # Creates: org.stage_members_instance(through_attrs: {})
          #
          # Stage creates a UUID-keyed through model and adds it to the staging set.
          # The participant doesn't exist yet (e.g., invitation sent but not accepted).
          #
          # @param target_class [Class] The target class (e.g., Organization)
          # @param collection_name [Symbol] Active collection name (e.g., :members)
          # @param staged_name [Symbol] Staging collection name (e.g., :pending_members)
          # @param through [Symbol, Class] Through model class
          def self.build_stage_method(target_class, collection_name, staged_name, through)
            method_name = "stage_#{collection_name}_instance"

            target_class.define_method(method_name) do |through_attrs: {}|
              through_class = Familia.resolve_class(through)
              staging_collection = send(staged_name)

              # Create UUID-keyed staged model
              staged_model = Participation::StagedOperations.stage(
                through_class: through_class,
                target: self,
                attrs: through_attrs,
              )

              # Add to staging set with created_at as score
              staging_collection.add(staged_model.objid, Familia.now.to_f)

              staged_model
            end
          end

          # Build method to activate a staged through model
          # Creates: org.activate_members_instance(staged_model, participant, through_attrs: {})
          #
          # Activation completes the relationship:
          # - ZADD to active collection with participant
          # - SADD to participant's reverse index
          # - ZREM from staging collection
          # - Create composite-keyed through model
          # - Destroy UUID-keyed staged model
          #
          # @param target_class [Class] The target class
          # @param collection_name [Symbol] Active collection name
          # @param staged_name [Symbol] Staging collection name
          # @param through [Symbol, Class] Through model class
          def self.build_activate_method(target_class, collection_name, staged_name, through)
            method_name = "activate_#{collection_name}_instance"

            target_class.define_method(method_name) do |staged_model, participant, through_attrs: {}|
              through_class = Familia.resolve_class(through)
              active_collection = send(collection_name)
              staging_collection = send(staged_name)

              # Calculate score for participant in active set
              score = if participant.respond_to?(:calculate_participation_score)
                participant.calculate_participation_score(self.class, collection_name)
              else
                Familia.now.to_f
              end

              # Transaction: sorted set operations (ZADD active + SADD participations + ZREM staging)
              transaction do |_tx|
                # Add to active collection
                TargetMethods::Builder.add_to_collection(
                  active_collection,
                  participant,
                  score: score,
                  type: :sorted_set,
                  target_class: self.class,
                  collection_name: collection_name,
                )

                # Track participation in reverse index
                if participant.respond_to?(:track_participation_in)
                  participant.track_participation_in(active_collection.dbkey)
                end

                # Remove from staging set and log warning if entry not found
                removed = staging_collection.remove(staged_model.objid)
                Familia.debug "[activate] Staging entry not found for #{staged_model.objid}" if removed == 0
              end

              # TRANSACTION BOUNDARY: Through model operations happen outside transaction
              # (same pattern as build_add_item - see that method for detailed rationale)
              Participation::StagedOperations.activate(
                through_class: through_class,
                staged_model: staged_model,
                target: self,
                participant: participant,
                attrs: through_attrs,
              )
            end
          end

          # Build method to unstage (revoke) a staged through model
          # Creates: org.unstage_members_instance(staged_model)
          #
          # Unstaging removes the through model from staging and destroys it.
          # Used when an invitation is revoked before acceptance.
          #
          # @param target_class [Class] The target class
          # @param collection_name [Symbol] Active collection name (for method naming)
          # @param staged_name [Symbol] Staging collection name
          # @param _through [Symbol, Class] Through model class (unused - kept for signature
          #   consistency with other builders like build_stage_method and build_activate_method)
          def self.build_unstage_method(target_class, collection_name, staged_name, _through)
            method_name = "unstage_#{collection_name}_instance"

            target_class.define_method(method_name) do |staged_model|
              staging_collection = send(staged_name)

              # Remove from staging set
              staging_collection.remove(staged_model.objid)

              # Destroy the through model
              Participation::StagedOperations.unstage(staged_model: staged_model)
            end
          end

          # Build method to bulk stage multiple through models
          # Creates: org.stage_members(through_attrs_list)
          #
          # Stages multiple invitations at once. Each entry in the list creates
          # a UUID-keyed through model and adds it to the staging set.
          #
          # Uses two-phase approach for efficiency:
          # - Phase 1: Create through models sequentially (save requires inspectable returns)
          # - Phase 2: Pipeline all ZADD calls (reduces N round-trips to 1)
          #
          # @param target_class [Class] The target class
          # @param collection_name [Symbol] Active collection name (for method naming)
          # @param staged_name [Symbol] Staging collection name
          # @param through [Symbol, Class] Through model class
          def self.build_bulk_stage_method(target_class, collection_name, staged_name, through)
            method_name = "stage_#{collection_name}"

            target_class.define_method(method_name) do |through_attrs_list|
              return [] if through_attrs_list.empty?

              through_class = Familia.resolve_class(through)
              staging_collection = send(staged_name)

              # Phase 1: Create through models sequentially (save requires inspectable returns)
              staged_models = through_attrs_list.map do |attrs|
                Participation::StagedOperations.stage(
                  through_class: through_class,
                  target: self,
                  attrs: attrs,
                )
              end

              # Phase 2: Pipeline all ZADD calls (reduces N round-trips to 1)
              pipelined do |_pipe|
                now = Familia.now.to_f
                staged_models.each { |m| staging_collection.add(m.objid, now) }
              end

              staged_models
            end
          end

          # Build method to bulk unstage multiple through models
          # Creates: org.unstage_members(staged_models_or_objids)
          #
          # Revokes multiple invitations at once. Accepts either staged model
          # objects or their objids (flexible). Returns count of models destroyed.
          #
          # Uses two-phase approach for efficiency:
          # - Phase 1: Pipeline all ZREM calls (reduces N round-trips to 1)
          # - Phase 2: Destroy models sequentially (load/exists?/destroy! need inspectable returns)
          #
          # @param target_class [Class] The target class
          # @param collection_name [Symbol] Active collection name (for method naming)
          # @param staged_name [Symbol] Staging collection name
          # @param through [Symbol, Class] Through model class
          def self.build_bulk_unstage_method(target_class, collection_name, staged_name, through)
            method_name = "unstage_#{collection_name}"

            target_class.define_method(method_name) do |staged_models_or_objids|
              return 0 if staged_models_or_objids.empty?

              through_class = Familia.resolve_class(through)
              staging_collection = send(staged_name)

              # Phase 1: Pipeline all ZREM calls (reduces N round-trips to 1)
              pipelined do |_pipe|
                staged_models_or_objids.each do |item|
                  objid = item.respond_to?(:objid) ? item.objid : item
                  staging_collection.remove(objid)
                end
              end

              # Phase 2: Destroy through models sequentially
              # StagedOperations.unstage returns true on success, false if model didn't exist
              staged_models_or_objids.count do |item|
                model = if item.respond_to?(:exists?)
                  item
                else
                  through_class.load(item.respond_to?(:objid) ? item.objid : item)
                end
                Participation::StagedOperations.unstage(staged_model: model) if model
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
