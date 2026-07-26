# lib/familia/features/relationships/indexing.rb
#
# frozen_string_literal: true

require_relative 'indexing_relationship'
require_relative 'indexing/multi_index_generators'
require_relative 'indexing/unique_index_generators'
require_relative 'indexing/rebuild_strategies'

module Familia
  module Features
    module Relationships
      # Indexing module for attribute-based lookups using Valkey/Redis data structures.
      # Provides O(1) field-to-object mappings without relationship semantics.
      #
      # @example Class-level unique index (1:1 mapping via HashKey)
      #   class User < Familia::Horreum
      #     feature :relationships
      #     field :email
      #     unique_index :email, :email_lookup
      #   end
      #
      #   user = User.new(user_id: 'u1', email: 'alice@example.com')
      #   user.save  # Automatically populates email_lookup index
      #   User.find_by_email('alice@example.com')  # → user
      #
      # @example Instance-scoped unique index (within parent, 1:1 via HashKey)
      #   class Employee < Familia::Horreum
      #     feature :relationships
      #     field :badge_number
      #     unique_index :badge_number, :badge_index, within: Company
      #   end
      #
      #   company = Company.new(company_id: 'c1')
      #   employee = Employee.new(emp_id: 'e1', badge_number: '12345')
      #   employee.add_to_company_badge_index(company)
      #   company.find_by_badge_number('12345')  # → employee
      #
      # @example Instance-scoped multi-value index (within parent, 1:many via UnsortedSet)
      #   class Employee < Familia::Horreum
      #     feature :relationships
      #     field :department
      #     multi_index :department, :dept_index, within: Company
      #   end
      #
      #   company = Company.new(company_id: 'c1')
      #   emp1 = Employee.new(emp_id: 'e1', department: 'engineering')
      #   emp2 = Employee.new(emp_id: 'e2', department: 'engineering')
      #   emp1.add_to_company_dept_index(company)
      #   emp2.add_to_company_dept_index(company)
      #   company.find_all_by_department('engineering')  # → [emp1, emp2]
      #
      # Terminology:
      # - unique_index: 1:1 field-to-object mapping (HashKey)
      # - multi_index: 1:many field-to-objects mapping (UnsortedSet, no scores)
      # - within: scope class providing uniqueness boundary for instance-scoped indexes
      # - query: whether to generate find_by_* methods (default: true)
      #
      # Key Patterns:
      # - Class unique: "user:email_index" → HashKey
      # - Instance unique: "company:c1:badge_index" → HashKey
      # - Instance multi: "company:c1:dept_index:engineering" → UnsortedSet
      #
      # Auto-Indexing:
      # Class-level unique_index declarations automatically populate on save():
      #   user = User.new(email: 'test@example.com')
      #   user.save  # Auto-indexes email → user_id
      # Instance-scoped indexes (with within:) require an initial manual
      # add_to_* call to establish the scope context, which save cannot invent.
      # From then on the membership is tracked in a reverse index tracker and
      # maintained automatically: save refreshes it (unique indexes retract the
      # stale entry via update_in_*; multi indexes are add-only) and destroy!
      # removes every tracked entry (#282).
      #
      # Design Philosophy:
      # Indexing is for finding objects by attribute, not ordering them.
      # Use multi_index with UnsortedSet (no temporal scores), then sort in Ruby:
      #   employees = company.find_all_by_department('eng')
      #   sorted = employees.sort_by(&:hire_date)

      module Indexing
        using Familia::Refinements::StylizeWords

        # Class-level indexing configurations
        def self.included(base)
          base.extend ModelClassMethods
          base.include ModelInstanceMethods
          super
        end

        # Indexing::ModelClassMethods
        #
        module ModelClassMethods
          # Define an indexed_by relationship for fast lookups
          #
          # Define a multi-value index (1:many mapping)
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index
          # @param within [Class, Symbol] The scope class providing uniqueness context
          # @param query [Boolean] Whether to generate query methods
          #
          # @example Instance-scoped multi-value indexing
          #   multi_index :department, :dept_index, within: Company
          #
          def multi_index(field, index_name, within: :class, query: true)
            MultiIndexGenerators.setup(
              indexed_class: self,
              field: field,
              index_name: index_name,
              within: within,
              query: query,
            )
          end

          # Define a unique index lookup (1:1 mapping)
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index hash
          # @param within [Class, Symbol] Optional scope class for instance-scoped unique index
          # @param query [Boolean] Whether to generate query methods
          #
          # @example Class-level unique index
          #   unique_index :email, :email_lookup
          #   unique_index :username, :username_lookup, query: false
          #
          # @example Instance-scoped unique index
          #   unique_index :badge_number, :badge_index, within: Company
          #
          def unique_index(field, index_name, within: nil, query: true)
            UniqueIndexGenerators.setup(
              indexed_class: self,
              field: field,
              index_name: index_name,
              within: within,
              query: query,
            )
          end

          # Get all indexing relationships for this class
          def indexing_relationships
            @indexing_relationships ||= []
          end

          # Ensure proper DataType field is declared for index
          # Similar to ensure_collection_field in participation system
          #
          # @param opts [Hash] Options forwarded to the DataType declaration
          #   (e.g. +class:+ and +reference: true+ so the index hashkey is a
          #   proper reference type that works with +each_record+).
          def ensure_index_field(scope_class, index_name, field_type, opts = {})
            return if scope_class.method_defined?(index_name) || scope_class.respond_to?(index_name)

            scope_class.send(field_type, index_name, opts)
          end
        end

        # Instance methods for indexed objects
        module ModelInstanceMethods
          # Update all indexes for a given scope context
          # For class-level indexes (unique_index without within:), scope_context should be nil
          # For instance-scoped indexes (with within:), scope_context should be the scope instance
          def update_all_indexes(old_values = {}, scope_context = nil)
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              field = config.field
              index_name = config.index_name
              old_field_value = old_values[field]

              if config.class_level?
                send("update_in_class_#{index_name}", old_field_value)
              else
                next unless scope_context

                scope_class_config = Familia.resolve_class(config.scope_class).config_name
                send("update_in_#{scope_class_config}_#{index_name}", scope_context, old_field_value)
              end
            end
          end

          # Remove from all indexes for a given scope context
          # For class-level indexes (unique_index without within:), scope_context should be nil
          # For instance-scoped indexes (with within:), scope_context should be the scope instance
          def remove_from_all_indexes(scope_context = nil)
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              index_name = config.index_name

              if config.class_level?
                send("remove_from_class_#{index_name}")
              else
                next unless scope_context

                scope_class_config = Familia.resolve_class(config.scope_class).config_name
                send("remove_from_#{scope_class_config}_#{index_name}", scope_context)
              end
            end
          end

          # Refresh instance-scoped indexes during save, for every scope
          # instance previously registered via add_to_*. The initial add_to_*
          # stays manual (save has no scope context to invent), but once a
          # membership is tracked, saving keeps it current.
          #
          # Called from inside save's MULTI/EXEC (via persist_to_storage), for
          # two reasons that both pin it there:
          #
          # 1. Dirty tracking is still live -- clear_dirty! runs after the
          #    transaction -- so the previous value of a changed indexed field
          #    is available to retract. The relationships save hook runs after
          #    the commit, where changed_fields is already empty.
          # 2. The index mutation commits atomically with the object hash.
          #
          # @param tracked_entries [Hash<String, String>] tracker entries
          #   pre-read OUTSIDE the transaction by read_instance_index_scopes.
          #   Passed in rather than read here: HGETALL inside MULTI returns
          #   futures, not values.
          # @return [void]
          def auto_update_instance_indexes(tracked_entries)
            return if tracked_entries.nil? || tracked_entries.empty?

            # { field => [old_value, new_value] }; still populated inside the
            # save transaction (see above).
            changes = changed_fields

            _each_tracked_membership(tracked_entries) do |config, scope_config, scope_instance|
              _apply_instance_index_change(config, scope_config, scope_instance, changes)
            end
          end

          # Yield each distinct instance-scoped membership in the tracker
          # exactly once, resolved to its relationship config and a scope stub.
          #
          # A multi index contributes one tracker entry per value bucket the
          # object occupies, but both callers work per MEMBERSHIP rather than
          # per bucket -- the refresh re-applies the object's current field
          # value, and the uniqueness guard validates that one value. Entries
          # are collapsed on the scope/index/scope_id triple so a record with
          # a long value history does not re-run the same work once per
          # historical bucket.
          #
          # @param tracked_entries [Hash<String, String>] pre-read tracker
          # @yieldparam config [IndexingRelationship]
          # @yieldparam scope_config [String]
          # @yieldparam scope_instance [Object] stub built from the tracker
          # @return [void]
          def _each_tracked_membership(tracked_entries)
            seen = {}

            tracked_entries.each_key do |entry|
              scope_config, idx_name, scope_id = _parse_index_scope_entry(entry)
              next unless scope_config && idx_name && scope_id

              membership = "#{scope_config}\t#{idx_name}\t#{scope_id}"
              next if seen.key?(membership)

              config = _find_instance_index_config(scope_config, idx_name)
              next unless config

              seen[membership] = true
              yield(config, scope_config, _build_scope_stub(config.scope_class, scope_id))
            end
          end

          # Validate instance-scoped unique constraints before save writes
          # anything. The instance-scoped counterpart to
          # Horreum::Persistence#guard_unique_indexes!, which only covers
          # class-level relationships.
          #
          # MUST be called OUTSIDE the save transaction: the guard reads the
          # scope's index hash, and reads inside MULTI return futures.
          #
          # Without this, save's auto-refresh reached update_in_* -- which has
          # no uniqueness guard, unlike add_to_* -- so changing an indexed
          # field to a value another record already held silently evicted that
          # record's entry. The evicted record's tracker still claimed the
          # slot, so its later destroy! unindexed the live winner. The
          # class-level path always raised here; this closes the asymmetry.
          #
          # Only changed fields are guarded. An unchanged value would be
          # validated against its own existing entry -- harmless, since the
          # guard compares existing_id to identifier, but it would also make
          # every save re-read every tracked index for no benefit, and would
          # start failing saves if an external actor took the slot.
          #
          # @param tracked_entries [Hash<String, String>] pre-read tracker
          # @raise [Familia::RecordExistsError] if a scope already maps the
          #   new value to a different record
          # @return [void]
          def guard_tracked_index_scopes!(tracked_entries)
            return if tracked_entries.nil? || tracked_entries.empty?

            changes = changed_fields

            _each_tracked_membership(tracked_entries) do |config, scope_config, scope_instance|
              # Multi indexes have no uniqueness to enforce.
              next unless config.cardinality == :unique
              next unless changes.key?(config.field)

              guard_method = :"guard_unique_#{scope_config}_#{config.index_name}!"
              send(guard_method, scope_instance) if respond_to?(guard_method)
            end
          end

          # Maintain a single instance-scoped index entry during save.
          #
          # Mirrors the class-level routing in
          # Horreum::Persistence#apply_class_index_change:
          #
          # - unique_index: route through update_in_* with the previous value
          #   so a changed indexed field retracts its stale entry. Otherwise
          #   find_by_<field>(old_value) resolves a tombstone and the freed
          #   value cannot be reused -- the unique guard sees the orphan.
          #   update_in_* always re-adds the current value, and its reentrant
          #   transaction joins this save's MULTI, so remove+add commit
          #   together.
          # - multi_index: add-only. A value change deliberately does NOT
          #   retract prior buckets, matching the class-level decision (see
          #   the class_level_multi_index tests); SADD is idempotent so
          #   repeated saves stay safe.
          #
          # @param config [IndexingRelationship] instance-scoped relationship
          # @param scope_config [String] scope class config name
          # @param scope_instance [Object] stub scope built from the tracker
          # @param changes [Hash] dirty-tracking diff
          # @return [void]
          def _apply_instance_index_change(config, scope_config, scope_instance, changes)
            update_method = :"update_in_#{scope_config}_#{config.index_name}"
            add_method = :"add_to_#{scope_config}_#{config.index_name}"

            if config.cardinality == :unique && respond_to?(update_method)
              change = changes[config.field]
              send(update_method, scope_instance, change && change.first)
            elsif respond_to?(add_method)
              send(add_method, scope_instance)
            end
          end

          # Read instance-scoped index tracker entries. Must be called
          # BEFORE entering a MULTI/EXEC transaction since HGETALL
          # inside MULTI returns futures, not values.
          #
          # Tracker cardinality mirrors index cardinality, so the tracker can
          # describe the true state rather than approximate it:
          #
          # - unique index (1:1): key is the
          #   "<scope_config>\t<index_name>\t<scope_id>" triple. The object
          #   occupies exactly one bucket per scope, and update_in_* retracts
          #   the old one, so HSET-overwrite is exact.
          # - multi index (1:many): key appends the value --
          #   "...\t<scope_id>\t<field_value>". Refresh is add-only, so after
          #   a value change the object really is in several buckets at once;
          #   a triple-keyed entry could only name one of them and destroy!
          #   would orphan the rest.
          #
          # Every value is the field value written into that index -- the
          # bucket to clean up. It is stored rather than re-read from the
          # object at cleanup time so removal still finds the right bucket
          # when the indexed field has since changed, or when the object was
          # loaded identifier-only and has no field values in memory.
          #
          # @return [Hash<String, String>] tracker entries, empty if none
          def read_instance_index_scopes
            return {} unless _has_instance_scoped_indexes?

            _index_scope_tracker.hgetall
          end

          # Remove instance-scoped index entries using pre-read tracker
          # data. Safe to call inside a MULTI/EXEC transaction since all
          # operations are writes (HDEL, SREM, DEL).
          #
          # @note Every key touched here (the scope's index, this object's
          #   tracker) must live in the same logical database as the caller's
          #   transaction -- the standing cross-database constraint on
          #   MULTI/EXEC (see AGENTS.md on atomic_write). A scope class
          #   configured with a different logical_database cannot participate.
          #   Note this now binds save as well as destroy!: before the
          #   instance-scoped refresh, save never touched scope-owned keys, so
          #   a cross-database scope was only a destroy!-time concern.
          #
          # @param tracked_entries [Hash<String, String>] entries from
          #   read_instance_index_scopes ({ entry key => indexed field value })
          def remove_tracked_index_entries!(tracked_entries)
            return if tracked_entries.nil? || tracked_entries.empty?

            tracked_entries.each do |entry, field_value|
              scope_config, idx_name, scope_id = _parse_index_scope_entry(entry)
              next unless scope_config && idx_name && scope_id

              config = _find_instance_index_config(scope_config, idx_name)
              next unless config

              scope_instance = _build_scope_stub(config.scope_class, scope_id)
              remove_method = :"remove_from_#{scope_config}_#{idx_name}"
              # Pass the RECORDED field value: send(field) may have changed
              # (or be nil on an identifier-only instance), which would target
              # the wrong bucket or skip removal entirely.
              send(remove_method, scope_instance, field_value.to_s) if respond_to?(remove_method)
            end

            _index_scope_tracker.delete!
          end

          # Record that this object was added to an instance-scoped index.
          # Called by the generated add_to_*/update_in_* methods.
          #
          # The tracker is a HashKey rather than a set so that re-recording an
          # existing membership is an idempotent upsert (HSET) and a specific
          # membership can be dropped by key (HDEL) without reading -- a set
          # could not be pruned inside destroy!'s MULTI, where SMEMBERS
          # returns futures.
          #
          # @param field_value [Object] the value written into the index
          # @param cardinality [Symbol] :unique or :multi -- decides whether
          #   the entry key includes the value (see #read_instance_index_scopes)
          def _record_index_scope(scope_config, index_name, scope_instance, field_value, cardinality:)
            _ensure_trackable_index_scope!(scope_instance)

            entry = _index_scope_entry(scope_config, index_name, scope_instance, field_value, cardinality)
            _index_scope_tracker[entry] = field_value.to_s
          end

          # Drop one tracking entry. Called by the generated remove_from_*
          # methods and by the multi update_in_* path when it retracts a
          # bucket.
          #
          # @param field_value [Object, nil] the bucket being left. Required
          #   on the :multi path -- it is part of the entry key, so omitting
          #   it would HDEL a field that does not exist and strand the entry.
          #   Ignored for :unique, whose key is the triple alone.
          def _unrecord_index_scope(scope_config, index_name, scope_instance, field_value, cardinality:)
            entry = _index_scope_entry(scope_config, index_name, scope_instance, field_value, cardinality)
            _index_scope_tracker.remove_field(entry)
          end

          # Tracker maintenance for the unique update_in_* path. One entry per
          # scope/index, so the new value overwrites it; a cleared field
          # leaves no index entry at all, so the tracker entry is dropped
          # rather than left pointing at a bucket destroy! would find empty.
          def _sync_unique_index_scope(scope_config, index_name, scope_instance, field_value)
            if field_value
              _record_index_scope(scope_config, index_name, scope_instance, field_value, cardinality: :unique)
            else
              _unrecord_index_scope(scope_config, index_name, scope_instance, nil, cardinality: :unique)
            end
          end

          # Tracker maintenance for the multi update_in_* path. Mirrors
          # exactly what update_in_* did to the index: it retracts the old
          # bucket only when an old value was supplied, and adds the new one.
          #
          # Note what does NOT come through here: the save refresh path calls
          # add_to_* (add-only), so entries for buckets the object still
          # occupies survive. Deleting them there would recreate the orphan
          # this per-value keying exists to prevent.
          def _sync_multi_index_scope(scope_config, index_name, scope_instance, old_field_value, new_field_value)
            if old_field_value
              _unrecord_index_scope(scope_config, index_name, scope_instance, old_field_value, cardinality: :multi)
            end
            return unless new_field_value

            _record_index_scope(scope_config, index_name, scope_instance, new_field_value, cardinality: :multi)
          end

          # Fail fast when this object has never been persisted. Called by the
          # generated add_to_*/update_in_* methods (both instance-scoped and
          # class-level variants) before any write. An index entry stores this
          # object's identifier, so indexing an unsaved object plants a
          # dangling pointer in the index — and if the process never saves, no
          # tracker entry or destroy! pass can find it to clean up.
          #
          # Skipped inside a transaction/pipeline, where the EXISTS probe would
          # queue into the caller's MULTI and return a Future instead of a
          # boolean (same conservatism as DataType#warn_if_dirty!). This is
          # also what keeps the save path working: auto_update_class_indexes
          # and the rebuild strategies call these methods inside a MULTI,
          # where the object hash write is queued alongside the index write.
          #
          # @param index_name [Symbol] the index being written
          # @param scope_instance [Object, nil] scope for instance-scoped
          #   indexes; nil for class-level indexes
          def _ensure_persisted_before_index_write!(index_name, scope_instance = nil)
            return if Fiber[:familia_transaction]
            return if exists?

            location = if scope_instance
                         "#{index_name} on #{scope_instance.class.name}"
                       else
                         "class-level #{index_name}"
                       end
            raise Familia::PersistenceError,
                  "Cannot index unsaved #{self.class.name} in #{location}: " \
                  'the index entry would point to a record that does not ' \
                  'exist in the database yet. Call #save first.'
          end

          # Fail fast when a scope instance cannot be tracked, and therefore
          # cannot be cleaned up on destroy!. Called at the TOP of the
          # generated instance-scoped add_to_*/update_in_* methods, before
          # any index write: guarding only at record time would leave the
          # index entry written and untracked -- exactly the orphan this
          # prevents.
          #
          # Three ways a scope is untrackable:
          #
          # 1. No identifier. The tracker entry (and the scope's index key)
          #    are built from it; a blank one yields an ambiguous entry that
          #    later resolves to a malformed key.
          # 2. A tab in the identifier. Tracker entries are tab-delimited and
          #    the identifier is an interior component, so a tab in it makes
          #    the entry ambiguous with a differently-shaped one -- a unique
          #    entry for scope id "aa\tbb" is byte-identical to a multi entry
          #    for scope id "aa" in bucket "bb", and parses back as scope id
          #    "aa". Destroying the former then deletes an unrelated scope's
          #    live index entry. (Interior only: see #_parse_index_scope_entry
          #    for why a tab in the field value is safe.)
          # 3. A non-simple identifier_field (e.g. a Proc). Cleanup runs
          #    inside destroy!'s MULTI and must rebuild the scope from its id
          #    string alone, with no reads -- only a Symbol/String
          #    identifier_field supports that.
          #
          # @param scope_instance [Object] the scope providing index context
          # @raise [Familia::NoIdentifier] if the scope has no identifier
          # @raise [ArgumentError] if the identifier contains a tab, or the
          #   scope class has no simple identifier field
          def _ensure_trackable_index_scope!(scope_instance)
            scope_id = scope_instance.identifier
            if scope_id.nil? || scope_id.to_s.empty?
              raise Familia::NoIdentifier,
                    "Cannot index within #{scope_instance.class}: the scope " \
                    'instance has no identifier. Instance-scoped index ' \
                    'entries are keyed by the scope identifier.'
            end

            if scope_id.to_s.include?("\t")
              raise ArgumentError,
                    "Cannot index within #{scope_instance.class} " \
                    "#{scope_id.inspect}: the scope identifier contains a tab. " \
                    'Index tracker entries are tab-delimited and the scope ' \
                    'identifier is an interior component, so a tab makes the ' \
                    "entry ambiguous with another scope's -- destroy! could " \
                    'then remove an unrelated index entry.'
            end

            _scope_identifier_field(scope_instance.class)
          end

          # The scope class's identifier field, validated as usable for
          # read-free stub construction.
          #
          # @return [Symbol]
          # @raise [ArgumentError] if the identifier field is not a Symbol/String
          def _scope_identifier_field(scope_class)
            id_field = scope_class.identifier_field
            unless id_field.is_a?(Symbol) || id_field.is_a?(String)
              raise ArgumentError,
                    "#{scope_class} cannot scope an index: its identifier_field " \
                    "is #{id_field.inspect}. Instance-scoped indexes require a " \
                    'simple (Symbol or String) identifier field, because ' \
                    'destroy! must rebuild the scope from its identifier alone ' \
                    'inside a transaction, where reads are unavailable.'
            end

            id_field.to_sym
          end

          # Tracker field identifying one index membership.
          #
          # Unique indexes are 1:1 within a scope, so the
          # scope/index/scope_id triple is the whole identity. Multi indexes
          # are 1:many -- the object can sit in several value buckets at once
          # -- so the value is part of the identity and each bucket gets its
          # own entry.
          #
          # @return [String]
          def _index_scope_entry(scope_config, index_name, scope_instance, field_value, cardinality)
            entry = "#{scope_config}\t#{index_name}\t#{scope_instance.identifier}"
            return entry unless cardinality == :multi

            "#{entry}\t#{field_value}"
          end

          # Split a tracker entry back into its membership parts.
          #
          # Limit 4, not 3: a multi entry carries a trailing value, and
          # split("\t", 3) would glue it onto scope_id -- silently corrupting
          # the scope identifier used to rebuild the stub. The value is not
          # returned because callers take it from the stored HSET value,
          # which is authoritative for both cardinalities.
          #
          # Internal format contract -- "<scope_config>\t<index_name>\t
          # <scope_id>" with an optional "\t<field_value>" for multi indexes:
          #
          # - scope_config and index_name are derived from class config names
          #   and declared index symbols, so they cannot contain a tab.
          # - scope_id is user-controlled and IS constrained: a tab in it is
          #   rejected up front by #_ensure_trackable_index_scope!, because as
          #   an interior component it would make entries ambiguous.
          # - field_value is user-controlled and is NOT constrained. It is the
          #   final component and the limit-4 split leaves it intact however
          #   many tabs it holds; it also never feeds key construction here
          #   (the stored HSET value is what removal uses), so ambiguity in it
          #   cannot misdirect a delete.
          #
          # @return [Array(String, String, String)] scope_config, index_name, scope_id
          def _parse_index_scope_entry(entry)
            entry.split("\t", 4).first(3)
          end

          # Locate the instance-scoped relationship a tracker entry refers to.
          #
          # Matches on scope config AND index name: two different scope
          # classes may share an index name, and matching on the name alone
          # would always resolve to whichever was declared first, building a
          # stub of the wrong class and mutating the wrong key.
          #
          # Resolves scope_class through Familia.resolve_class for consistency
          # with the surrounding call sites (#update_all_indexes,
          # #remove_from_all_indexes), which resolve the same way.
          # IndexingRelationship#scope_class_config_name would also work --
          # the DSL resolves `within:` at declaration time and stores a Class,
          # so it is never an unresolved Symbol here.
          def _find_instance_index_config(scope_config, idx_name)
            self.class.indexing_relationships.find do |rel|
              next false if rel.class_level?
              next false unless rel.index_name.to_s == idx_name

              Familia.resolve_class(rel.scope_class).config_name.to_s == scope_config
            end
          end

          def _has_instance_scoped_indexes?
            return false unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.any? { |rel| !rel.class_level? }
          end

          # ORM-internal bookkeeping, not user data -- hence
          # dirty_write_warnings: :off. Save refreshes tracked indexes from
          # inside its own MULTI, where the object is dirty by design (dirty
          # tracking is what supplies the old value to retract). The default
          # diagnostic would fire on every such save telling the caller to
          # "call #save first", and under strict_write_order it would raise
          # and abort the save outright.
          def _index_scope_tracker
            @_index_scope_tracker ||= Familia::HashKey.new(
              Familia.join('_idx_scopes'), parent: self, dirty_write_warnings: :off
            )
          end

          # Build a minimal scope instance for Redis key resolution without
          # loading the full object from the database. Write-only by design:
          # this runs inside destroy!'s MULTI, where any read would return a
          # Redis::Future rather than a value. Scope classes that cannot be
          # rebuilt this way are rejected up front (see
          # _ensure_trackable_index_scope!), so there is no read fallback.
          def _build_scope_stub(scope_class, scope_id)
            klass = Familia.resolve_class(scope_class)
            klass.new(_scope_identifier_field(klass) => scope_id)
          end
          # All internal. The public surface of this module is deliberately
          # narrow: read_instance_index_scopes, remove_tracked_index_entries!,
          # auto_update_instance_indexes and guard_tracked_index_scopes! stay
          # public because Horreum::Persistence reaches them through
          # respond_to?, which does not see private methods.
          private :_index_scope_tracker, :_build_scope_stub, :_has_instance_scoped_indexes?,
                  :_ensure_trackable_index_scope!, :_scope_identifier_field,
                  :_index_scope_entry, :_parse_index_scope_entry,
                  :_find_instance_index_config, :_apply_instance_index_change,
                  :_each_tracked_membership,
                  :_record_index_scope, :_unrecord_index_scope,
                  :_sync_unique_index_scope, :_sync_multi_index_scope

          # Get all indexes this object appears in
          # Note: For instance-scoped indexes, this only shows class-level indexes
          # since instance-scoped indexes require a specific scope instance
          #
          # @return [Array<Hash>] Array of index information
          def current_indexings
            return [] unless self.class.respond_to?(:indexing_relationships)

            memberships = []

            self.class.indexing_relationships.each do |config|
              field = config.field
              index_name = config.index_name
              cardinality = config.cardinality
              field_value = send(field)

              next unless field_value

              # Class-level indexes have within: nil (unique_index) or within: :class (multi_index)
              # Instance-scoped indexes have within: SomeClass (a specific class)
              if config.within.nil? || config.within == :class
                if cardinality == :unique
                  # Class-level unique index - check hash key using DataType
                  index_hash = self.class.send(index_name)
                  next unless index_hash.key?(field_value.to_s)

                  memberships << {
                    scope_class: 'class',
                    index_name: index_name,
                    field: field,
                    field_value: field_value,
                    index_key: index_hash.dbkey,
                    cardinality: cardinality,
                    type: 'unique_index',
                  }
                else
                  # Class-level multi index - check set membership using factory method
                  index_set = self.class.send("#{index_name}_for", field_value)
                  next unless index_set.member?(identifier)

                  memberships << {
                    scope_class: 'class',
                    index_name: index_name,
                    field: field,
                    field_value: field_value,
                    index_key: index_set.dbkey,
                    cardinality: cardinality,
                    type: 'multi_index',
                  }
                end
              else
                # Instance-scoped index (unique_index or multi_index with within:) - cannot check without scope instance
                # This would require scanning all possible scope instances
                memberships << {
                  scope_class: config.scope_class_config_name,
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: 'scope_dependent',
                  cardinality: cardinality,
                  type: cardinality == :unique ? 'unique_index' : 'multi_index',
                  note: 'Requires scope instance for verification',
                }
              end
            end

            memberships
          end

          # Check if this object is indexed in a specific scope
          # For class-level indexes, checks the hash key (unique) or set membership (multi)
          # For instance-scoped indexes, returns false (requires scope instance)
          def indexed_in?(index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel.index_name == index_name }
            return false unless config

            field = config.field
            field_value = send(field)
            return false unless field_value

            # Class-level indexes have within: nil (unique_index) or within: :class (multi_index)
            # Instance-scoped indexes have within: SomeClass (a specific class)
            if config.within.nil? || config.within == :class
              if config.cardinality == :unique
                # Class-level unique index - check hash key using DataType
                index_hash = self.class.send(index_name)
                index_hash.key?(field_value.to_s)
              else
                # Class-level multi index - check set membership using factory method
                index_set = self.class.send("#{index_name}_for", field_value)
                index_set.member?(identifier)
              end
            else
              # Instance-scoped index (with within:) - cannot verify without scope instance
              false
            end
          end
        end
      end
    end
  end
end
