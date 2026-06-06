# lib/familia/index_descriptor.rb
#
# frozen_string_literal: true

module Familia
  # IndexDescriptor pairs an owning Horreum class with one of its
  # IndexingRelationship configs and exposes behavior that hides the index's
  # method-naming and storage internals — iteration, rebuild, and format
  # checks. The IndexingRelationship itself has no back-reference to its owner,
  # so this wrapper supplies that pairing for project-wide use.
  #
  # Obtain descriptors via the project-wide aggregators
  # (Familia.unique_indexes, Familia.index_descriptors, ...) rather than
  # constructing them directly.
  #
  # @example Rebuild every class-level unique index in the app (requires 2.10.1+)
  #   Familia.unique_indexes(class_level: true).each(&:rebuild!)
  #
  # @example Iterate the records behind a class-level unique index
  #   idx = Familia.unique_indexes(owner: User).first
  #   idx.each_record { |user| user.notify! }
  #
  IndexDescriptor = Data.define(:owner, :relationship) do
    # --- Delegated metadata (read-only views of the IndexingRelationship) ---

    def field        = relationship.field
    def index_name   = relationship.index_name
    def cardinality  = relationship.cardinality
    def within       = relationship.within
    def scope_class  = relationship.scope_class
    def query?       = relationship.query
    def class_level? = relationship.class_level?
    def unique?      = cardinality == :unique
    def multi?       = cardinality == :multi

    # Stable "Owner:index_name" coordinate, e.g. "User:email_lookup".
    #
    # @return [String]
    def coordinate
      Familia.join(owner.name, index_name)
    end

    # Iterate the indexed records, resolving the right backing collection so
    # callers never touch +send(index_name)+ or the +_for+ factory:
    #
    # - class-level unique -> owner.<index_name>            (HashKey, reference)
    # - class-level multi  -> owner.<index_name>_for(value) (UnsortedSet) [value:]
    # - instance-scoped    -> requires scope: (the within instance)
    #
    # @param value [Object, nil] required for multi_index (selects the bucket)
    # @param scope [Familia::Horreum, nil] required for instance-scoped indexes
    # @param opts [Hash] forwarded to the collection's #each_record
    # @return [Enumerator, Object] Enumerator without a block, else the collection
    def each_record(value: nil, scope: nil, **opts, &block)
      backing(value: value, scope: scope).each_record(**opts, &block)
    end

    # Rebuild this index from the source of truth, delegating to the generated
    # +rebuild_<index_name>+ method. Class-level indexes rebuild on the owner;
    # instance-scoped indexes require the scope instance.
    #
    # @param scope [Familia::Horreum, nil] required for instance-scoped indexes
    # @param opts [Hash] forwarded to the generated rebuilder (e.g. batch_size:)
    # @return [Integer] count of indexed records
    # @raise [Familia::Problem] for instance-scoped indexes called without a
    #   scope, or for `query: false` indexes (which generate no rebuilder)
    def rebuild!(scope: nil, **opts)
      target = resolve_target(scope)
      rebuilder = :"rebuild_#{index_name}"
      unless target.respond_to?(rebuilder)
        raise Familia::Problem,
              "#{coordinate} has no generated rebuilder (declared query: false). " \
              'Migrate it by re-saving the affected records, or declare it query: true.'
      end

      target.public_send(rebuilder, **opts)
    end

    # Whether the index's stored data predates the current (raw) storage format
    # — i.e. still holds legacy JSON-encoded identifiers from pre-2.10.0 writes.
    # Samples raw values without deserializing, so no read-time warnings fire.
    #
    # Only class-level unique indexes have a single backing key that can be
    # sampled without a value/scope; multi and instance-scoped indexes return
    # false here (check them per-bucket / per-scope with #each_record).
    #
    # @param sample [Integer] number of raw values to sample
    # @return [Boolean]
    def stale_format?(sample: 100)
      return false unless class_level? && unique?

      sample_raw_values(sample).any? { |v| Familia.legacy_json_encoded?(v) }
    end

    # Convenience inverse of #stale_format?.
    #
    # @return [Boolean]
    def format_current?(**opts)
      !stale_format?(**opts)
    end

    private

    def resolve_target(scope)
      return scope if scope
      raise Familia::Problem, "#{coordinate} is instance-scoped; pass scope:" unless class_level?

      owner
    end

    def backing(value:, scope:)
      if class_level?
        return owner.public_send(index_name) if unique?
        raise ArgumentError, "#{coordinate} is a multi_index; pass value:" if value.nil?

        owner.public_send(:"#{index_name}_for", value)
      else
        raise Familia::Problem, "#{coordinate} is instance-scoped; pass scope:" if scope.nil?
        return scope.public_send(index_name) if unique?
        raise ArgumentError, "#{coordinate} is a multi_index; pass value:" if value.nil?

        scope.public_send(:"#{index_name}_for", value)
      end
    end

    # Read raw stored values (no deserialize -> no legacy-strip warnings).
    # Samples field names with HRANDFIELD, then fetches their raw values with
    # HMGET. Both return unambiguous flat arrays, sidestepping the
    # version-dependent shape of HRANDFIELD ... WITHVALUES.
    def sample_raw_values(count)
      hk = owner.public_send(index_name)
      fields = Array(hk.dbclient.hrandfield(hk.dbkey, count))
      return [] if fields.empty?

      hk.dbclient.hmget(hk.dbkey, *fields)
    end
  end

  # Project-wide relationship introspection, extended onto Familia.
  #
  # Per-class metadata already lives on each model (indexing_relationships,
  # participation_relationships). These helpers aggregate it across the whole
  # clan (Familia.members) and return descriptors that act without the caller
  # knowing Familia's index method-naming or storage layout.
  module Introspection
    # All index descriptors across every loaded Horreum subclass.
    #
    # @param cardinality [Symbol, nil] filter by :unique or :multi
    # @param class_level [Boolean, nil] filter class-level (true) vs scoped (false)
    # @param owner [Class, nil] restrict to a single owning class
    # @return [Array<Familia::IndexDescriptor>]
    def index_descriptors(cardinality: nil, class_level: nil, owner: nil)
      members.flat_map do |klass|
        next [] unless klass.respond_to?(:indexing_relationships)
        next [] if owner && klass != owner

        klass.indexing_relationships.filter_map do |rel|
          next if cardinality && rel.cardinality != cardinality
          next if !class_level.nil? && rel.class_level? != class_level

          IndexDescriptor.new(owner: klass, relationship: rel)
        end
      end
    end

    # Unique (1:1) index descriptors across the clan.
    #
    # @param class_level [Boolean, nil] class-level (true) vs instance-scoped (false)
    # @param owner [Class, nil] restrict to a single owning class
    # @return [Array<Familia::IndexDescriptor>]
    def unique_indexes(class_level: nil, owner: nil)
      index_descriptors(cardinality: :unique, class_level: class_level, owner: owner)
    end

    # Multi-value (1:many) index descriptors across the clan.
    #
    # @param class_level [Boolean, nil] class-level (true) vs instance-scoped (false)
    # @param owner [Class, nil] restrict to a single owning class
    # @return [Array<Familia::IndexDescriptor>]
    def multi_indexes(class_level: nil, owner: nil)
      index_descriptors(cardinality: :multi, class_level: class_level, owner: owner)
    end

    # Participation relationships across the clan, paired with their owners.
    #
    # @param owner [Class, nil] restrict to a single owning class
    # @return [Array<Array(Class, ParticipationRelationship)>]
    def participation_descriptors(owner: nil)
      members.flat_map do |klass|
        next [] unless klass.respond_to?(:participation_relationships)
        next [] if owner && klass != owner

        klass.participation_relationships.map { |rel| [klass, rel] }
      end
    end

    # Class-level unique indexes whose stored data predates the current format
    # (legacy JSON-encoded identifiers) and therefore need a rebuild.
    #
    # Scoped to `query: true` indexes: those are the ones with a generated
    # `find_by_*` that can silently miss on stale data (the failure this guards
    # against), and the only ones with a generated rebuilder. A `query: false`
    # index has no `find_by_*`, self-heals on read, and is migrated by re-saving
    # records — so it is intentionally excluded here.
    #
    # @param sample [Integer] raw values sampled per index
    # @param owner [Class, nil] restrict to a single owning class
    # @return [Array<Familia::IndexDescriptor>]
    def stale_indexes(sample: 100, owner: nil)
      unique_indexes(class_level: true, owner: owner)
        .select(&:query?)
        .reject { |idx| idx.format_current?(sample: sample) }
    end

    # Boot guard / CI smoke test: ensure no class-level unique index holds
    # stale-format data. Raises (default) or warns when drift is found. This is
    # the safeguard that surfaces an un-rebuilt index before a lookup silently
    # fails at runtime.
    #
    # @param sample [Integer] raw values sampled per index
    # @param owner [Class, nil] restrict the check to a single owning class
    # @param on_stale [Symbol] :raise (default) or :warn
    # @return [Boolean] true when all checked indexes are current
    # @raise [ArgumentError] when on_stale is not :raise or :warn
    # @raise [Familia::Problem] when stale indexes are found and on_stale: :raise
    #
    # @example Fail fast at boot
    #   Familia.assert_indexes_current!
    #
    # @example Non-fatal CI smoke test
    #   Familia.assert_indexes_current!(on_stale: :warn)
    def assert_indexes_current!(sample: 100, owner: nil, on_stale: :raise)
      unless %i[raise warn].include?(on_stale)
        raise ArgumentError, "on_stale: must be :raise or :warn; got #{on_stale.inspect}"
      end

      stale = stale_indexes(sample: sample, owner: owner)
      return true if stale.empty?

      msg = "Stale unique indexes need rebuild: #{stale.map(&:coordinate).join(', ')}. " \
            'See docs/migrating/v2.10.md (Unique-index storage format).'
      raise Familia::Problem, msg unless on_stale == :warn

      Familia.warn "[familia] #{msg}"
      false
    end
  end

  extend Introspection
end
