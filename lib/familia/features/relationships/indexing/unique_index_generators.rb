# lib/familia/features/relationships/indexing/unique_index_generators.rb
#
# frozen_string_literal: true

require_relative 'rebuild_strategies'

module Familia
  module Features
    module Relationships
      module Indexing
        # Generators for unique index (1:1) methods
        #
        # Unique indexes use HashKey DataType for field-to-object identifier mapping.
        # Each field value maps to exactly one object identifier.
        #
        # Example (instance-scoped):
        #   unique_index :badge_number, :badge_index, within: Company
        #
        # Generates on Company (destination):
        #   - company.find_by_badge_number(badge)
        #   - company.find_all_by_badge_number([badges])
        #   - company.badge_index
        #   - company.rebuild_badge_index
        #
        # Generates on Employee (self):
        #   - employee.add_to_company_badge_index(company)
        #   - employee.remove_from_company_badge_index(company)
        #   - employee.update_in_company_badge_index(company, old_badge)
        #
        # Example (class-level):
        #   unique_index :email, :email_index
        #
        # Generates on Employee (class):
        #   - Employee.find_by_email(email)
        #   - Employee.find_all_by_email([emails])
        #   - Employee.email_index
        #   - Employee.rebuild_email_index
        #
        # Generates on Employee (self):
        #   - employee.add_to_class_email_index (called automatically on save)
        #   - employee.remove_from_class_email_index
        #   - employee.update_in_class_email_index(old_email)
        #
        # Note: Class-level indexes auto-populate on save(). Instance-scoped indexes
        # (with within:) require an initial manual add_to_* call; afterwards save
        # auto-refreshes the tracked entry and destroy! auto-cleans it, both via
        # the reverse index tracker (#282).
        module UniqueIndexGenerators
          module_function

          using Familia::Refinements::StylizeWords

          # Main setup method that orchestrates unique index creation
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index
          # @param index_name [Symbol] Name of the index
          # @param within [Class, Symbol, nil] Scope class for instance-scoped index
          # @param query [Boolean] Whether to generate query methods
          def setup(indexed_class:, field:, index_name:, within:, query:)
            # Normalize parameters and determine scope type
            scope_class, scope_type = if within
              k = Familia.resolve_class(within)
              [k, :instance]
            else
              [indexed_class, :class]
            end

            # Store metadata for this indexing relationship
            indexed_class.indexing_relationships << IndexingRelationship.new(
              field:             field,
              scope_class:       scope_class,
              within:            within,
              index_name:        index_name,
              query:             query,
              cardinality:       :unique,
            )

            # Generate appropriate methods based on scope type
            case scope_type
            when :instance
              # Instance-scoped index (within: Company)
              if query && scope_class.is_a?(Class)
                generate_query_methods_destination(indexed_class, field, scope_class, index_name)
              end
              generate_mutation_methods_self(indexed_class, field, scope_class, index_name)
            when :class
              # Class-level index (no within:)
              #
              # Declare the backing hashkey as a reference type pointing at the
              # indexed class. The index maps field_value => object identifier,
              # so `class: indexed_class, reference: true` lets the stored
              # identifiers round-trip as raw strings and enables `each_record`
              # to load the indexed records via load_multi.
              indexed_class.send(
                :ensure_index_field, indexed_class, index_name, :class_hashkey,
                class: indexed_class, reference: true
              )
              generate_query_methods_class(field, index_name, indexed_class) if query
              generate_mutation_methods_class(field, index_name, indexed_class)
            end
          end

          # Generates query methods ON THE SCOPE CLASS (Company when within: Company)
          #
          # - company.find_by_badge_number(badge) - find by field value
          # - company.find_all_by_badge_number([badges]) - batch lookup
          # - company.badge_index - DataType accessor
          # - company.rebuild_badge_index - rebuild index
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :badge_number)
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :badge_index)
          def generate_query_methods_destination(indexed_class, field, scope_class, index_name)
            # Resolve scope class using Familia pattern
            actual_scope_class = Familia.resolve_class(scope_class)

            # Ensure the index field is declared (creates accessor that returns DataType).
            # The hashkey lives on the scope class but maps field_value => identifier
            # of the indexed class, so declare it as a reference type pointing at
            # indexed_class (raw identifier round-trip + each_record support).
            actual_scope_class.send(
              :ensure_index_field, actual_scope_class, index_name, :hashkey,
              class: indexed_class, reference: true
            )

            # Get scope_class_config for method naming (needed for rebuild methods)
            scope_class_config = actual_scope_class.config_name

            # Generate instance query method (e.g., company.find_by_badge_number)
            actual_scope_class.class_eval do
              define_method(:"find_by_#{field}") do |provided_value|
                # Use declared field accessor instead of manual instantiation
                index_hash = send(index_name)

                # Get the identifier from the hash using .get method.
                # We use .get instead of [] because it's part of the standard interface
                # common across all DataType classes (List, UnsortedSet, SortedSet, HashKey).
                # While unique indexes always use HashKey, using .get maintains consistency
                # with the broader DataType API patterns used throughout Familia.
                record_id = index_hash.get(provided_value)
                return nil unless record_id

                indexed_class.find_by_identifier(record_id)
              end

              # Generate bulk query method (e.g., company.find_all_by_badge_number)
              define_method(:"find_all_by_#{field}") do |provided_ids|
                # Convert to array and filter nil inputs before querying Redis.
                # This prevents wasteful lookups for empty string keys (nil.to_s → "").
                # Output may contain fewer elements than input (standard ORM behavior).
                provided_ids = Array(provided_ids).compact
                return [] if provided_ids.empty?

                # Use declared field accessor instead of manual instantiation
                index_hash = send(index_name)

                # Get all identifiers from the hash
                record_ids = index_hash.values_at(*provided_ids.map(&:to_s))

                # Filter out nil values (non-existent records) and instantiate objects
                record_ids.compact.map { |record_id|
                  indexed_class.find_by_identifier(record_id)
                }
              end

              # Accessor method already created by ensure_index_field above
              # No need to manually define it here

              # Generate method to rebuild the unique index for this parent instance
              define_method(:"rebuild_#{index_name}") do |batch_size: 100, &progress_block|
                # Find the collection containing the indexed class.
                #
                # Strategy 1: Check if indexed_class has a participation relationship
                # pointing back to this scope class. Participation relationships are
                # stored on the PARTICIPANT class (indexed_class), not the target.
                #
                # Example: When RebuildTestEmployee.participates_in(RebuildTestCompany, :employees),
                # the relationship is stored on RebuildTestEmployee, and we need to find it
                # by matching target_class (RebuildTestCompany) with self.class.
                collection = nil
                if indexed_class.respond_to?(:participation_relationships)
                  participation = indexed_class.participation_relationships.find do |rel|
                    rel.target_class == self.class
                  end

                  if participation
                    collection = send(participation.collection_name)
                  end
                end

                # Strategy 2: Fallback to checking related_fields for an explicit
                # record_class:/class: option matching the indexed class.
                # (participates_in collections carry record_class:; reference
                # collections carry class:.)
                unless collection
                  if self.class.respond_to?(:related_fields)
                    self.class.related_fields&.each do |name, field_def|
                      if [field_def.opts[:record_class], field_def.opts[:class]].include?(indexed_class)
                        collection = send(name)
                        break
                      end
                    end
                  end
                end

                if collection
                  # Find the IndexingRelationship to get cardinality metadata
                  index_config = indexed_class.indexing_relationships.find { |rel| rel.index_name == index_name }

                  # Strategy 2: Use participation-based rebuild
                  index_hashkey = send(index_name)  # Get the index HashKey for serialization
                  Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_participation(
                    self,                                      # scope_instance (e.g., company)
                    indexed_class,                             # e.g., Employee
                    field,                                     # e.g., :badge_number
                    :"add_to_#{scope_class_config}_#{index_name}",  # e.g., :add_to_company_badge_index
                    collection,
                    index_config.cardinality,                  # :unique or :multi
                    index_hashkey,                             # Pass index for serialization
                    batch_size: batch_size,
                    &progress_block
                  )
                else
                  # Strategy 3: Fall back to SCAN with filtering
                  index_hashkey = send(index_name)  # Get the index HashKey for serialization
                  Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_scan(
                    indexed_class,
                    field,
                    :"add_to_#{scope_class_config}_#{index_name}",
                    index_hashkey,                             # Pass index for serialization
                    scope_instance: self,
                    batch_size: batch_size,
                    &progress_block
                  )
                end
              end
            end
          end

          # Generates mutation methods ON THE INDEXED CLASS (Employee)
          #
          # Instance methods for scope-scoped unique index operations:
          # - employee.add_to_company_badge_index(company) - automatically validates uniqueness
          # - employee.remove_from_company_badge_index(company)
          # - employee.update_in_company_badge_index(company, old_badge)
          # - employee.guard_unique_company_badge_index!(company) - manual validation
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :badge_number)
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :badge_index)
          def generate_mutation_methods_self(indexed_class, field, scope_class, index_name)
            scope_class_config = scope_class.config_name
            indexed_class.class_eval do
              method_name = :"add_to_#{scope_class_config}_#{index_name}"
              Familia.debug("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                # Before any write: an untrackable scope produces an index
                # entry that destroy! could never find again.
                _ensure_trackable_index_scope!(scope_instance)

                field_value = send(field)
                return unless field_value

                _ensure_persisted_before_index_write!(index_name, scope_instance)

                index_hash = scope_instance.send(index_name)

                if Fiber[:familia_transaction]
                  # Inside a MULTI neither the read guard nor the CAS can run
                  # (both need a verdict, and queued commands only return
                  # Futures). Instance-scoped indexes are populated explicitly,
                  # so there is no pre-transaction claim to lean on the way
                  # class-level indexes have prepare_for_save. Write blindly and
                  # say so -- this is the documented escape hatch, and it does
                  # not enforce uniqueness.
                  Familia.debug <<~LOG_MESSAGE
                    [#{self.class}] add_to_#{scope_class_config}_#{index_name} inside a transaction writes without a uniqueness check. Call it outside the MULTI for the server-side CAS.
                  LOG_MESSAGE
                  index_hash[field_value.to_s] = identifier
                else
                  # Fast-fail read, then the CAS that actually enforces it.
                  guard_method = :"guard_unique_#{scope_class_config}_#{index_name}!"
                  send(guard_method, scope_instance) if respond_to?(guard_method)

                  outcome = index_hash.claim_field(field_value.to_s, identifier)
                  unless outcome.is_a?(Symbol)
                    raise Familia::RecordExistsError.new(
                      "#{self.class} exists in #{scope_instance.class} with #{field}=#{field_value}",
                      existing_id: outcome,
                    )
                  end
                end

                # Only reached when the value is ours: a lost claim raises
                # above, so destroy! never inherits a tracker entry for an
                # index entry another record owns.
                _record_index_scope(scope_class_config, index_name, scope_instance, field_value,
                                    cardinality: :unique)
              end

              # Add a guard method to enforce unique constraint on this instance-scoped index
              #
              # @param scope_instance [Object] The scope instance providing uniqueness context (e.g., a Company)
              # @raise [Familia::RecordExistsError] if a record with the same field value
              #   exists in the scope's index. Values are compared as strings.
              # @return [void]
              #
              # @example
              #   employee.guard_unique_company_badge_index!(company)
              #
              method_name = :"guard_unique_#{scope_class_config}_#{index_name}!"
              Familia.debug("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                field_value = send(field)
                return unless field_value

                # Use declared field accessor on scope instance
                index_hash = scope_instance.send(index_name)
                existing_id = index_hash.get(field_value.to_s)

                if existing_id && existing_id != identifier
                  raise Familia::RecordExistsError.new(
                    "#{self.class} exists in #{scope_instance.class} with #{field}=#{field_value}",
                    existing_id: existing_id,
                  )
                end
              end

              method_name = :"remove_from_#{scope_class_config}_#{index_name}"
              Familia.debug("[UniqueIndexGenerators] #{name} method #{method_name}")

              # @param scope_instance [Object] the scope holding the index
              # @param field_value [Object, nil] the value to unindex. Defaults
              #   to the object's current field value, preserving the public
              #   single-argument call. destroy! cleanup passes the value
              #   recorded at index time instead, since the current one may
              #   have changed (or be nil on an identifier-only instance).
              define_method(method_name) do |scope_instance, field_value = nil|
                return unless scope_instance

                field_value = send(field) if field_value.nil?
                return unless field_value

                index_hash = scope_instance.send(index_name)

                # Ownership-checked delete, so a stale in-memory field value
                # cannot evict an entry another record now owns.
                index_hash.release_field(field_value.to_s, identifier)

                # Untracked either way. If the entry belonged to another
                # record, release_field left it alone and this object has no
                # business pointing destroy! at it.
                _unrecord_index_scope(scope_class_config, index_name, scope_instance, field_value,
                                      cardinality: :unique)
              end

              method_name = :"update_in_#{scope_class_config}_#{index_name}"
              Familia.debug("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance, old_field_value = nil|
                return unless scope_instance

                _ensure_trackable_index_scope!(scope_instance)

                new_field_value = send(field)
                index_hash = scope_instance.send(index_name)

                # Claim before the MULTI opens (see ADR-0002). Inside an outer
                # transaction there is nothing to claim against, so the writes
                # below are unenforced -- same escape hatch as add_to_*.
                if new_field_value && !Fiber[:familia_transaction]
                  outcome = index_hash.claim_field(new_field_value.to_s, identifier)
                  unless outcome.is_a?(Symbol)
                    raise Familia::RecordExistsError.new(
                      "#{self.class} exists in #{scope_instance.class} with #{field}=#{new_field_value}",
                      existing_id: outcome,
                    )
                  end
                end

                _ensure_persisted_before_index_write!(index_name, scope_instance)

                # Use Familia's transaction method for atomicity with DataType abstraction
                scope_instance.transaction do |_tx|
                  # Release old value if provided (ownership-checked)
                  index_hash.release_field(old_field_value.to_s, identifier) if old_field_value

                  # Re-affirm the claimed value
                  index_hash[new_field_value.to_s] = identifier if new_field_value
                end

                # Keep the tracker pointing at what is actually in the index.
                #
                # Synced outside the block above, which behaves differently
                # depending on the caller. Standalone, scope_instance.transaction
                # opens a MULTI on the SCOPE's connection -- a tracker write
                # inside it would go to the wrong connection, since the tracker
                # belongs to this object. The tradeoff is that standalone, the
                # tracker sync is NOT atomic with the index write. During save
                # the block is reentrant (it joins the caller's MULTI via
                # Fiber[:familia_transaction]) so both land in that one
                # transaction and the tradeoff does not apply.
                _sync_unique_index_scope(scope_class_config, index_name, scope_instance, new_field_value)
              end
            end
          end

          # Generates query methods ON THE INDEXED CLASS (Employee):
          # Class-level methods (singleton):
          # - Employee.find_by_email(email)
          # - Employee.find_all_by_email([emails])
          # - Employee.email_index
          # - Employee.rebuild_email_index
          def generate_query_methods_class(field, index_name, indexed_class)
            # Generate class-level single record method
            indexed_class.define_singleton_method(:"find_by_#{field}") do |provided_id|
              index_hash = send(index_name) # access the class-level hashkey DataType

              # Get the identifier from the db hashkey using .get method.
              #
              # We use .get instead of [] because it's part of the standard interface
              # common across all DataType classes (List, UnsortedSet, SortedSet, HashKey).
              # While unique indexes always use HashKey, using .get maintains consistency
              # with the broader DataType API patterns used throughout Familia.
              record_id = index_hash.get(provided_id)

              return nil unless record_id

              indexed_class.find_by_identifier(record_id)
            end

            # Generate class-level bulk query method
            indexed_class.define_singleton_method(:"find_all_by_#{field}") do |provided_ids|
              # Convert to array and filter nil inputs before querying Redis.
              # This prevents wasteful lookups for empty string keys (nil.to_s → "").
              # Output may contain fewer elements than input (standard ORM behavior).
              provided_ids = Array(provided_ids).compact
              return [] if provided_ids.empty?

              index_hash = send(index_name) # access the class-level hashkey DataType

              # Get multiple identifiers from the db hashkey using .values_at
              record_ids = index_hash.values_at(*provided_ids.map(&:to_s))

              # Filter out nil values (non-existent records) and instantiate objects
              record_ids.compact.map { |record_id|
                indexed_class.find_by_identifier(record_id)
              }
            end

            # The index accessor method is already created by the class_hashkey declaration
            # No need to manually create it - Horreum handles this automatically

            # Generate method to rebuild the class-level index
            indexed_class.define_singleton_method(:"rebuild_#{index_name}") do |batch_size: 100, &progress_block|
              if respond_to?(:instances)
                # Strategy 1: Use instances collection (fastest)
                index_hashkey = send(index_name)  # Get the index HashKey for serialization
                Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_instances(
                  self,                                 # indexed_class (e.g., User)
                  field,                                # e.g., :email
                  :"add_to_class_#{index_name}",       # e.g., :add_to_class_email_lookup
                  index_hashkey,                        # Pass index for serialization
                  batch_size: batch_size,
                  &progress_block
                )
              else
                # Strategy 3: Fall back to SCAN
                index_hashkey = send(index_name)  # Get the index HashKey for serialization
                Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_scan(
                  self,
                  field,
                  :"add_to_class_#{index_name}",
                  index_hashkey,                        # Pass index for serialization
                  batch_size: batch_size,
                  &progress_block
                )
              end
            end
          end

          # Generates mutation methods ON THE INDEXED CLASS (Employee):
          # Instance methods for class-level index operations:
          # - employee.add_to_class_email_index
          # - employee.remove_from_class_email_index
          # - employee.update_in_class_email_index(old_email)
          def generate_mutation_methods_class(field, index_name, indexed_class)
            indexed_class.class_eval do
              # Atomically claim this record's current field value in the index.
              #
              # This is where the unique constraint is actually enforced: a
              # server-side CAS (HashKey#claim_field) that checks and writes in
              # one EVAL, so two concurrent savers of the same value cannot both
              # observe "unclaimed". guard_unique_*! reads before this and is a
              # fast-fail courtesy; this is the enforcement.
              #
              # Must run OUTSIDE a MULTI -- an EVAL queued inside one cannot
              # abort the other queued commands, and its verdict is a Future.
              # See docs/adr/0002-watch-for-private-keys-lua-for-shared-keys.md.
              #
              # @return [Symbol, nil] :created when the entry was newly written,
              #   :owned when this record already held it, nil when the record
              #   has no value for the indexed field.
              # @raise [Familia::RecordExistsError] if another record owns the value
              define_method(:"claim_unique_#{index_name}!") do
                field_value = send(field)
                return nil unless field_value

                index_hash = self.class.send(index_name)
                outcome = index_hash.claim_field(field_value.to_s, identifier)

                unless outcome.is_a?(Symbol)
                  raise Familia::RecordExistsError.new(
                    "#{self.class} exists #{field}=#{field_value}",
                    existing_id: outcome,
                  )
                end

                # Record which value was claimed, so a later in-MULTI HSET can
                # verify it is re-affirming *this* value and not one that was
                # assigned after the claim was taken. Recording here (rather
                # than in Persistence#claim_unique_indexes!) is what makes a
                # direct claim_unique_<index>! call sufficient on its own.
                record_unique_index_claim(index_name, field_value)

                outcome
              end

              # Release this record's claim on its current field value.
              #
              # Ownership-checked: an entry another record now legitimately owns
              # is left alone. Safe to queue inside a MULTI (it needs no return
              # value to decide anything).
              #
              # @return [Integer, Redis::Future, nil]
              define_method(:"release_unique_#{index_name}!") do
                field_value = send(field)
                return nil unless field_value

                ret = self.class.send(index_name).release_field(field_value.to_s, identifier)

                # The claim is gone, so the ledger must stop vouching for it --
                # otherwise a later in-MULTI write would "re-affirm" a claim
                # this record no longer holds, over whoever took the value next.
                forget_unique_index_claim(index_name, field_value)

                ret
              end

              define_method(:"add_to_class_#{index_name}") do
                field_value = send(field)

                return unless field_value

                _ensure_persisted_before_index_write!(index_name)

                unless Fiber[:familia_transaction]
                  # Outside a transaction the CAS *is* the write -- claim_field
                  # HSETs on success, so there is nothing left to do.
                  #
                  # `next` (not `return`) exits a define_method body with a
                  # value. Both work here -- define_method gives the block
                  # method semantics for `return` -- but `next` is the form that
                  # stays correct if this body is ever passed around as a Proc.
                  next send(:"claim_unique_#{index_name}!")
                end

                # Inside a MULTI this can only re-affirm the value claimed
                # before the transaction opened (prepare_for_save does that for
                # every save path). Without that claim the HSET below is the old
                # blind write, so refuse rather than reopen the TOCTOU. The
                # check is value-aware: a block that changed the indexed field
                # after prepare_for_save holds no claim on the new value.
                unless unique_index_claimed?(index_name, field_value)
                  raise Familia::OperationModeError, <<~ERROR_MESSAGE
                    Cannot add_to_class_#{index_name} inside a transaction without first claiming #{field.inspect}=#{field_value.inspect}. Call claim_unique_#{index_name}! outside the MULTI (see ADR-0002); the in-transaction HSET only re-affirms a claim on this exact value. If you changed #{field} inside an atomic_write block, set it before the block instead -- prepare_for_save claims the value the record holds when the block opens.
                  ERROR_MESSAGE
                end

                self.class.send(index_name)[field_value.to_s] = identifier
              end

              # Add a guard method to enforce unique constraint on this specific index
              #
              # Read-only pre-check. It runs for every unique index BEFORE any
              # claim is written (see Persistence#prepare_for_save), which is
              # what keeps a class with two unique indexes from writing a claim
              # for the first one and then failing on the second. Load-bearing,
              # not redundant with claim_unique_*!.
              #
              # @raise [Familia::RecordExistsError] if a record with the same
              # field value exists. Values are compared as strings.
              #
              # @return [void]
              define_method(:"guard_unique_#{index_name}!") do
                field_value = send(field)
                return unless field_value

                index_hash = self.class.send(index_name)
                existing_id = index_hash.get(field_value.to_s)

                if existing_id && existing_id != identifier
                  raise Familia::RecordExistsError.new(
                    "#{self.class} exists #{field}=#{field_value}",
                    existing_id: existing_id,
                  )
                end
              end

              define_method(:"remove_from_class_#{index_name}") do
                # Ownership-checked delete, and it must also clear the claim
                # ledger -- hence the delegation rather than a bare
                # release_field. A blind HDEL here lets a stale in-memory field
                # value evict a claim another record has since taken (the
                # release-side twin of the TOCTOU claim_field closes on the way
                # in), and a release that left the ledger intact would let this
                # record write the value back over the new owner from inside a
                # later transaction.
                send(:"release_unique_#{index_name}!")
              end

              define_method(:"update_in_class_#{index_name}") do |old_field_value = nil|
                new_field_value = send(field)

                _ensure_persisted_before_index_write!(index_name)

                # Claim before the MULTI. This is the path save takes (see
                # Persistence#apply_class_index_change), and inside the save's
                # transaction prepare_for_save has already claimed -- the HSET
                # below is then an idempotent re-affirmation. A caller who
                # opened their own MULTI without claiming gets an error rather
                # than the old blind write.
                if new_field_value
                  if !Fiber[:familia_transaction]
                    send(:"claim_unique_#{index_name}!")
                  elsif !unique_index_claimed?(index_name, new_field_value)
                    raise Familia::OperationModeError, <<~ERROR_MESSAGE
                      Cannot update_in_class_#{index_name} inside a transaction without first claiming #{field.inspect}=#{new_field_value.inspect}. Call claim_unique_#{index_name}! outside the MULTI (see ADR-0002); the in-transaction HSET only re-affirms a claim on this exact value. If you changed #{field} inside an atomic_write block, set it before the block instead -- prepare_for_save claims the value the record holds when the block opens.
                    ERROR_MESSAGE
                  end
                end

                # Use class-level transaction for atomicity with DataType abstraction
                self.class.transaction do |_tx|
                  index_hash = self.class.send(index_name) # Access the class-level hashkey DataType

                  # Release old value if provided (ownership-checked). The
                  # forget is value-matched, so it drops a ledger entry still
                  # pointing at the OLD value while leaving the claim on the
                  # new one -- which is the entry the HSET below re-affirms.
                  if old_field_value
                    index_hash.release_field(old_field_value.to_s, identifier)
                    forget_unique_index_claim(index_name, old_field_value)
                  end

                  # Re-affirm the claimed value
                  index_hash[new_field_value.to_s] = identifier if new_field_value
                end
              end
            end
          end
        end
      end
    end
  end
end
