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
        # ├── domains                              # Get the domains collection
        # ├── add_domains_instance(domain, score)  # Add one domain to my collection
        # ├── remove_domains_instance(domain)      # Remove one domain from my collection
        # ├── add_domains([...])                   # Bulk add domains
        # ├── domains_with_permission(flag)        # Query by permission flag (sorted_set only)
        # └── each_domains_with_permission(flag)   # Stream by permission flag via ZSCAN (sorted_set only)
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
          # @param participant_class [Class, nil] The participant class whose
          #   identifiers populate the collection. Threaded through so the
          #   collection is declared with record_class: (enables +each_record+
          #   without changing read semantics; see issue #297).
          # @param max_length [Integer, nil] Cap for the collection (issue
          #   #351). Threaded to ensure_collection_field, which validates it
          #   eagerly and raises on conflict with a pre-declared cap.
          # rubocop:disable Metrics/ParameterLists -- mirrors participates_in's surface; every param is threaded through
          def self.build(target_class, collection_name, type, through = nil, staged = nil,
                         participant_class: nil, max_length: nil)
            # rubocop:enable Metrics/ParameterLists
            # FIRST: Ensure the DataType field is defined on the target class.
            # Declared with record_class: so `each_record` can load participants.
            TargetMethods::Builder.ensure_collection_field(
              target_class, collection_name, type,
              participant_class: participant_class, max_length: max_length
            )

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
            build_permission_enumerator(target_class, collection_name)
          end

          # Build class-level collection methods (for class_participates_in)
          # @param target_class [Class] The class receiving these methods
          # @param collection_name [Symbol] Name of the collection
          # @param type [Symbol] Collection type
          # @param max_length [Integer, nil] Cap for the collection (issue
          #   #351), validated eagerly; raises on conflict with a pre-declared
          #   class-level cap (symmetry with ensure_collection_field).
          def self.build_class_level(target_class, collection_name, type, max_length: nil)
            validate_max_length_option!(type, max_length)

            # FIRST: Ensure the class-level DataType field is defined.
            # The collection holds instances of target_class itself. Declare it
            # with record_class: so `each_record` can load the records (issue
            # #297) without changing read deserialization — see
            # CollectionOperations#ensure_collection_field for why participation
            # uses record_class: rather than class: + reference: true.
            #
            # Skip if a class-level accessor already exists, mirroring the
            # method_defined? guard in ensure_collection_field so a pre-declared
            # collection is not silently overridden (symmetry with instance-level).
            if target_class.respond_to?(collection_name)
              existing = target_class.class_related_fields[collection_name.to_s.to_sym]
              assert_compatible_cap!(existing, max_length, target_class, collection_name, type,
                                     dsl: "class_#{type}")
            else
              opts = { record_class: target_class }
              opts[:max_length] = max_length if max_length
              target_class.send("class_#{type}", collection_name, **opts)
            end

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
          #
          # min_permission takes an atomic PERMISSION_FLAG (:read, :write,
          # :delete, ...). It is validated eagerly (before the limit: 0
          # shortcut and any scan, so it raises even on an empty collection)
          # and forwarded per-member to ScoreEncoding.permission?, so a
          # PERMISSION_ROLE (:viewer, :editor, :moderator) raises ArgumentError
          # rather than being expanded to its bits -- deliberately, since
          # permission? tests bits individually and would answer "holds any of
          # these" where the caller means "holds all of these". Pass the flag you
          # mean (:edit, not :editor). :admin names a flag as well as a role and
          # so resolves to bit 7 alone; see the "Flags versus roles" section in
          # ScoreEncoding for the full rationale.
          # Pagination is additive and backward compatible: the default call
          # (no kwargs) returns the same Array as before, but pages internally
          # so peak intermediate memory is O(batch_size) instead of O(N)
          # (issue #309).
          #
          # @param limit [Integer, nil] Max matching members to return
          #   (nil = no cap; all pages are scanned but memory stays bounded).
          # @param offset [Integer] Matching members to skip, applied
          #   POST-FILTER (skips members that pass the permission test, not
          #   raw sorted-set entries).
          # @param batch_size [Integer] Page size for the internal
          #   ZRANGEBYSCORE ... LIMIT loop.
          def self.build_permission_query(target_class, collection_name)
            method_name = "#{collection_name}_with_permission"

            target_class.define_method(method_name) do |min_permission = :read, limit: nil, offset: 0, batch_size: 500|
              TargetMethods::Builder.validate_min_permission!(min_permission)
              TargetMethods::Builder.validate_permission_query_args!(
                limit: limit, offset: offset, batch_size: batch_size,
              )
              return [] if limit&.zero?

              TargetMethods::Builder.filter_by_permission(
                send(collection_name), min_permission,
                limit: limit, offset: offset, batch_size: batch_size
              )
            end
          end

          # Validate min_permission eagerly, before any shortcut or scan loop,
          # so an invalid flag raises even when limit: 0 or the collection is
          # empty -- the lazy per-member permission? check never runs in those
          # cases. Delegates to permission_level_value so the role-vs-flag
          # ArgumentError message stays identical to the per-member path.
          # @api private
          def self.validate_min_permission!(min_permission)
            ScoreEncoding.permission_level_value(min_permission)
            nil
          end

          # Validate the pagination kwargs for *_with_permission (issue #309).
          # Mirrors the validation style in CollectionBase#each_record.
          # @api private
          def self.validate_permission_query_args!(limit:, offset:, batch_size:)
            unless batch_size.is_a?(Integer) && batch_size.positive?
              raise ArgumentError, "batch_size must be a positive integer (got #{batch_size.inspect})"
            end
            unless offset.is_a?(Integer) && !offset.negative?
              raise ArgumentError, "offset must be a non-negative integer (got #{offset.inspect})"
            end
            return if limit.nil? || (limit.is_a?(Integer) && !limit.negative?)

            raise ArgumentError, "limit must be nil or a non-negative integer (got #{limit.inspect})"
          end

          # Collect members whose scores carry min_permission, in score order,
          # applying offset (POST-FILTER: counts members that pass the
          # permission test, not raw entries) and limit.
          # @api private
          def self.filter_by_permission(collection, min_permission, limit:, offset:, batch_size:)
            matches = []
            skipped = 0

            each_permitted_pair(collection, min_permission, batch_size) do |raw_member, _score|
              if skipped < offset
                skipped += 1
                next
              end

              matches << collection.deserialize_value(raw_member)
              return matches if limit && matches.size >= limit
            end

            matches
          end

          # Yield [raw_member, score] pairs holding min_permission, one
          # ZRANGEBYSCORE page at a time so peak memory is O(batch_size).
          #
          # Permission bits are encoded in the FRACTIONAL part of each score
          # (see ScoreEncoding) and do not form a contiguous range, so a
          # score-range query (e.g. ZRANGEBYSCORE x +inf) cannot filter by
          # permission -- it would match members regardless of their bits.
          # Fetch members page by page and test the bits per-member.
          #
          # Pagination is offset-based (LIMIT page*batch_size, batch_size) on
          # purpose. Do NOT switch to score-cursor pagination with an
          # exclusive bound ("(#{score}"): encode_score truncates timestamps
          # to integer seconds, so members added in the same second with the
          # same permission bits share IDENTICAL scores, and an exclusive
          # bound would silently drop members straddling a page boundary. The
          # O(N²/batch) deep-offset CPU cost is the accepted trade for
          # correctness and bounded memory.
          # @api private
          def self.each_permitted_pair(collection, min_permission, batch_size)
            page = 0

            loop do
              raw_pairs = collection.rangebyscoreraw(
                '-inf', '+inf',
                limit: [page * batch_size, batch_size], with_scores: true
              )
              break if raw_pairs.empty?

              raw_pairs.each do |raw_member, score|
                yield raw_member, score if ScoreEncoding.permission?(score, min_permission)
              end

              break if raw_pairs.size < batch_size

              page += 1
            end
          end

          # Build streaming permission query for sorted sets (issue #309)
          # Creates: customer.each_domains_with_permission(min_level) { |d| ... }
          #
          # Streams members via ZSCAN, so retained memory is O(1) regardless
          # of collection size. ZSCAN trade-offs (vs the Array-returning
          # <collection>_with_permission):
          # - Iteration order is UNORDERED (not score order).
          # - Delivery is at-least-once: a member may be yielded more than
          #   once if the sorted set is rehashed mid-scan (duplicates
          #   possible); members present for the whole scan are never missed.
          #
          # min_permission semantics match build_permission_query above:
          # atomic PERMISSION_FLAGs only, roles raise ArgumentError.
          def self.build_permission_enumerator(target_class, collection_name)
            method_name = "each_#{collection_name}_with_permission"

            target_class.define_method(method_name) do |min_permission = :read, batch_size: 100, &block|
              TargetMethods::Builder.validate_min_permission!(min_permission)
              unless batch_size.is_a?(Integer) && batch_size.positive?
                raise ArgumentError, "batch_size must be a positive integer (got #{batch_size.inspect})"
              end

              unless block
                return to_enum(:"each_#{collection_name}_with_permission", min_permission, batch_size: batch_size)
              end

              collection = send(collection_name)
              cursor = 0
              loop do
                cursor, pairs = collection.scan(cursor, count: batch_size)
                # ZSCAN yields an Array of [member, score] pairs (not a Hash);
                # SortedSet#scan already deserializes members and coerces
                # scores to Float, so yield the member directly. NB: if this
                # loop ever stops using `score`, Style/HashEachMethods will
                # want to autocorrect it to each_key, which raises
                # NoMethodError on an Array — disable the cop, don't obey it
                # (see the guard in SortedSet#each).
                pairs.each do |member, score|
                  block.call(member) if ScoreEncoding.permission?(score, min_permission)
                end
                break if cursor.zero?
              end

              self
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
