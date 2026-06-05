# frozen_string_literal: true

module Familia
  class DataType
    # CollectionBase - Base module for iterable DataType classes
    #
    # Collection types represent multi-value structures in Redis (LIST, SET,
    # ZSET, HASH). They include Enumerable and provide batch iteration via
    # each_record for reference collections.
    #
    # Each collection type must implement its own `each` method that:
    # - Yields elements to the block when given
    # - Returns an Enumerator when no block given
    #
    # @example Collection types
    #   ListKey     - Redis LIST
    #   UnsortedSet - Redis SET
    #   SortedSet   - Redis ZSET
    #   HashKey     - Redis HASH
    #
    module CollectionBase
      def self.included(base)
        base.include(Enumerable)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def collection_type?
          # Check ancestors to handle inheritance
          ancestors.include?(Familia::DataType::CollectionBase)
        end
      end

      def collection_type?
        self.class.collection_type?
      end

      # Iterates over identifiers, loading each as a Horreum record.
      #
      # This method is designed for DataTypes that store object identifiers.
      # It requires the collection to know which class to hydrate, supplied by
      # either the `record_class:` option (a loading-only hint that does not
      # change read deserialization — used by `participates_in`) or the `class:`
      # option on a `reference: true` collection (e.g. `instances`,
      # `unique_index`). It loads records in batches using the record class's
      # `load_multi` method and yields each loaded record.
      #
      # Ghost identifiers (where the underlying key has expired) are silently
      # filtered out.
      #
      # @param batch_size [Integer] Number of identifiers to load per batch
      # @param pipeline [Integer, nil] Controls pipelining depth for writes
      #   in the block. When nil (default), writes are serial (no pipelining).
      #   When a positive integer, fast writers in the block will be pipelined
      #   in groups of this size. Must not exceed batch_size.
      # @param filters [Hash] Additional filter parameters passed to `each`.
      #   Available filters depend on the collection type:
      #   - SortedSet: `since:`, `until:`, `cursor_batch_size:`
      #   - UnsortedSet/HashKey: `matching:`, `cursor_batch_size:`
      #   - ListKey: `cursor_batch_size:` only
      #   Passing unsupported filters raises ArgumentError.
      # @yield [record] Each loaded Horreum record (non-nil)
      # @return [Enumerator, self] Returns Enumerator if no block given, self otherwise
      #
      # @example Iterate over all records (no pipelining, safe default)
      #   User.instances.each_record { |user| user.deactivate! }
      #
      # @example With time filter (for SortedSet)
      #   User.instances.each_record(since: 1.day.ago) { |u| notify(u) }
      #
      # @example Pipeline writes in groups
      #   items.each_record(batch_size: 500, pipeline: 50) { |r| r.foo! 'bar' }
      #
      def each_record(batch_size: 100, pipeline: nil, **filters, &block)
        return to_enum(:each_record, batch_size: batch_size, pipeline: pipeline, **filters) unless block

        # Determine the class to load records from.
        #
        # Two opts can supply it, in priority order:
        #   - :record_class — a loading-only hint. It tells each_record which
        #     class to hydrate, WITHOUT affecting how the collection deserializes
        #     reads (members/member?/score keep the generic DataType semantics).
        #     Used by participates_in collections (issue #297).
        #   - :class — set alongside `reference: true` for true reference
        #     collections (e.g. `instances`, unique_index), where raw-string read
        #     semantics are also wanted.
        #
        # load_multi is identifier-type-tolerant (it builds keys via dbkey), so
        # whichever path `each` yields the identifier through, loading works.
        record_class = @opts[:record_class] || @opts[:class]
        unless record_class&.respond_to?(:load_multi)
          raise Familia::Problem, "each_record requires a DataType with a :record_class (or :class) option that responds to load_multi"
        end

        # Validate batch_size and pipeline constraints
        raise ArgumentError, "batch_size must be a positive integer (got #{batch_size.inspect})" unless batch_size.is_a?(Integer) && batch_size.positive?
        raise ArgumentError, "pipeline must be nil or a positive integer (got #{pipeline.inspect})" unless pipeline.nil? || (pipeline.is_a?(Integer) && pipeline.positive?)
        raise ArgumentError, "pipeline (#{pipeline}) cannot exceed batch_size (#{batch_size})" if pipeline&.> batch_size

        # Collect identifiers in batches
        buffer = []

        process_batch = lambda do |ids|
          return if ids.empty?

          # Load records using the class's load_multi (pipelined HGETALLs)
          records = record_class.load_multi(ids)

          # Filter out ghosts (nil results from expired keys)
          live_records = records.compact

          if pipeline.nil?
            # Serial mode - no pipelining, execute block for each record directly
            live_records.each { |record| block.call(record) }
          else
            # Pipelined mode - group records and wrap each group in a pipeline
            live_records.each_slice(pipeline) do |group|
              record_class.pipelined do
                group.each { |record| block.call(record) }
              end
            end
          end
        end

        # Iterate using the type's each method with any filters
        each(**filters) do |member|
          # HashKey yields [field, value] pairs where the value is the stored
          # object identifier (e.g. unique_index maps field_value => identifier),
          # so extract the value. List/Set/SortedSet yield the identifier directly.
          identifier = member.is_a?(Array) ? member.last : member
          buffer << identifier

          if buffer.size >= batch_size
            process_batch.call(buffer)
            buffer.clear
          end
        end

        # Process remaining items
        process_batch.call(buffer) unless buffer.empty?

        self
      end
    end
  end
end
