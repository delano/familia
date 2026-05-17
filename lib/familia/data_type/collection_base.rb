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
      # This method is designed for DataTypes that store object identifiers
      # (typically with `reference: true`). It loads records in batches using
      # the parent class's `load_multi` method and yields each loaded record.
      #
      # Ghost identifiers (where the underlying key has expired) are silently
      # filtered out.
      #
      # @param batch_size [Integer] Number of identifiers to load per batch
      # @param write_size [Integer, nil] Controls pipelining depth for writes
      #   in the block. When nil or 0, writes are serial (no pipelining).
      #   When positive, fast writers in the block will be pipelined in
      #   groups of this size.
      # @param filters [Hash] Additional filter parameters passed to `each`.
      #   Available filters depend on the collection type:
      #   - SortedSet: `since:`, `until:`, `cursor_batch_size:`
      #   - UnsortedSet/HashKey: `matching:`, `cursor_batch_size:`
      #   - ListKey: `cursor_batch_size:` only
      #   Passing unsupported filters raises ArgumentError.
      # @yield [record] Each loaded Horreum record (non-nil)
      # @return [Enumerator, self] Returns Enumerator if no block given, self otherwise
      #
      # @example Iterate over all records
      #   User.instances.each_record { |user| user.deactivate! }
      #
      # @example With time filter (for SortedSet)
      #   User.instances.each_record(since: 1.day.ago) { |u| notify(u) }
      #
      # @example Pipeline writes in groups
      #   items.each_record(batch_size: 500, write_size: 50) { |r| r.foo! 'bar' }
      #
      # @example Serial writes (no pipelining)
      #   items.each_record(write_size: nil) { |r| r.save }
      #
      def each_record(batch_size: 100, write_size: batch_size, **filters, &block)
        return to_enum(:each_record, batch_size: batch_size, write_size: write_size, **filters) unless block

        # Determine the class to load records from
        # For reference DataTypes, @opts[:class] holds the Horreum class
        record_class = @opts[:class]
        unless record_class&.respond_to?(:load_multi)
          raise Familia::Problem, "each_record requires a reference DataType with a :class option that responds to load_multi"
        end

        # Validate write_size constraints
        if write_size && write_size > batch_size
          raise ArgumentError, "write_size (#{write_size}) cannot exceed batch_size (#{batch_size})"
        end

        # Collect identifiers in batches
        buffer = []

        process_batch = lambda do |ids|
          return if ids.empty?

          # Load records using the class's load_multi (pipelined HGETALLs)
          records = record_class.load_multi(ids)

          # Filter out ghosts (nil results from expired keys)
          live_records = records.compact

          if write_size.nil? || write_size.zero?
            # Serial mode - no pipelining, execute block for each record directly
            live_records.each { |record| block.call(record) }
          else
            # Pipelined mode - group records and wrap each group in a pipeline
            live_records.each_slice(write_size) do |group|
              record_class.pipelined do
                group.each { |record| block.call(record) }
              end
            end
          end
        end

        # Iterate using the type's each method with any filters
        each(**filters) do |member|
          # HashKey yields [field, value] pairs; extract field as identifier
          identifier = member.is_a?(Array) ? member.first : member
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
