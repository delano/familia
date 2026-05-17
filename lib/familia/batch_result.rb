# lib/familia/batch_result.rb
#
# frozen_string_literal: true

module Familia
  # Represents the result of a batch iteration operation.
  #
  # BatchResult tracks statistics and errors when processing multiple records
  # via methods like `each_record`. It provides aggregated metrics for the
  # entire batch run, distinct from MultiResult which wraps a single
  # MULTI/EXEC or pipeline operation.
  #
  # @attr_reader scanned [Integer] Total number of items iterated
  # @attr_reader modified [Integer] Count of items where block returned truthy
  # @attr_reader errors [Array<Hash>] Per-item errors as [{id:, error:}, ...]
  # @attr_reader duration_ms [Float] Total elapsed time in milliseconds
  #
  # @example Using BatchResult.collect
  #   result = BatchResult.collect(User.instances) do |user|
  #     user.deactivate!
  #   end
  #   puts "Processed #{result.scanned}, modified #{result.modified}"
  #   puts "Errors: #{result.errors.size}" if result.errors?
  #
  # @example With strict mode
  #   # Re-raises first error after completing iteration
  #   BatchResult.collect(items, strict: true) { |item| item.process! }
  #
  class BatchResult
    attr_reader :scanned, :modified, :errors, :duration_ms

    # Creates a new BatchResult instance.
    #
    # @param scanned [Integer] Total items processed
    # @param modified [Integer] Items where block returned truthy
    # @param errors [Array<Hash>] Array of error hashes with :id and :error keys
    # @param duration_ms [Float] Elapsed time in milliseconds
    def initialize(scanned:, modified:, errors:, duration_ms:)
      @scanned = scanned
      @modified = modified
      @errors = errors
      @duration_ms = duration_ms
    end

    # Iterates over an enumerable, collecting statistics and errors.
    #
    # This is the primary factory method for creating BatchResult instances.
    # It tracks how many items were processed, how many returned truthy values,
    # and captures any exceptions that occur during iteration.
    #
    # @param enumerable [Enumerable] The collection to iterate
    # @param strict [Boolean] When true, re-raises the first captured error
    #   after iteration completes. Default: false.
    # @yield [item] Each item from the enumerable
    # @yieldreturn [Object] Truthy return values increment the modified count
    # @return [BatchResult] Aggregated result of the batch operation
    #
    # @example Basic usage
    #   result = BatchResult.collect(records) { |r| r.update!(status: 'done') }
    #
    # @example Strict mode re-raises errors
    #   begin
    #     BatchResult.collect(records, strict: true) { |r| r.validate! }
    #   rescue => e
    #     puts "Batch failed: #{e.message}"
    #   end
    #
    def self.collect(enumerable, strict: false)
      scanned = 0
      modified = 0
      errors = []
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      enumerable.each do |*args|
        scanned += 1
        begin
          result = yield(*args)
          modified += 1 if result
        rescue StandardError => e
          # Extract identifier if possible
          identifier = extract_identifier(args.length == 1 ? args[0] : args)
          errors << { id: identifier, error: e }
        end
      end

      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

      batch_result = new(
        scanned: scanned,
        modified: modified,
        errors: errors,
        duration_ms: duration_ms
      )

      # In strict mode, re-raise the first error after completing iteration
      raise errors.first[:error] if strict && errors.any?

      batch_result
    end

    # Checks if any errors occurred during the batch.
    #
    # @return [Boolean] true if at least one error was captured
    def errors?
      !errors.empty?
    end

    # Checks if the batch completed without errors.
    #
    # @return [Boolean] true if no errors occurred
    def successful?
      errors.empty?
    end
    alias success? successful?

    # Returns the count of items that were scanned but not modified.
    #
    # @return [Integer] Number of items where block returned falsy
    def skipped
      scanned - modified - errors.size
    end

    # Returns a hash representation of the result.
    #
    # @return [Hash] Result data including all metrics
    def to_h
      {
        scanned: scanned,
        modified: modified,
        skipped: skipped,
        errors: errors.size,
        duration_ms: duration_ms.round(2),
        successful: successful?
      }
    end

    # Returns a human-readable summary.
    #
    # @return [String] Summary of the batch operation
    def to_s
      "BatchResult: scanned=#{scanned} modified=#{modified} errors=#{errors.size} duration=#{duration_ms.round(2)}ms"
    end

    # @private
    def self.extract_identifier(item)
      if item.respond_to?(:identifier)
        item.identifier
      elsif item.respond_to?(:id)
        item.id
      else
        item.to_s[0, 50]
      end
    rescue StandardError
      nil
    end
    private_class_method :extract_identifier
  end
end
