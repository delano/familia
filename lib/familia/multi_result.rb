# lib/familia/multi_result.rb
#
# frozen_string_literal: true

module Familia
  # Represents the result of a Valkey/Redis transaction or pipeline operation.
  #
  # This class encapsulates the outcome of a Database multi-command operation,
  # providing access to both the command results and derived success status
  # based on the presence of errors in the results.
  #
  # Success is determined by checking for Exception objects in the results array.
  # When Redis commands fail within a transaction or pipeline, they return
  # exception objects rather than raising them, allowing other commands to
  # continue executing.
  #
  # A third outcome exists for transactions: an *aborted* MULTI. redis-rb
  # returns nil (not an array) from #multi when EXEC is discarded, which is the
  # documented result of a WATCH-guarded transaction whose watched key was
  # modified by another client. Such a result carries no command return values
  # at all, so it is neither successful nor a carrier of errors -- see
  # {#aborted?}.
  #
  # @attr_reader results [Array, nil] Array of return values from the Database commands.
  #   Values can be strings, integers, booleans, or Exception objects for failed commands.
  #   nil when the transaction was aborted before EXEC ran.
  #
  # @example Creating a MultiResult instance
  #   result = Familia::MultiResult.new(["OK", "OK", 1])
  #
  # @example Checking transaction success
  #   if result.successful?
  #     puts "All commands completed without errors"
  #   else
  #     puts "#{result.errors.size} command(s) failed"
  #   end
  #
  # @example Accessing individual command results
  #   result.results.each_with_index do |value, index|
  #     puts "Command #{index + 1} returned: #{value}"
  #   end
  #
  # @example Inspecting errors
  #   if result.errors?
  #     result.errors.each do |error|
  #       puts "Error: #{error.message}"
  #     end
  #   end
  #
  # @example Handling a WATCH-aborted transaction
  #   result = Familia::MultiResult.new(nil)
  #   result.aborted?     # => true
  #   result.successful?  # => false
  #   result.errors       # => []
  #
  class MultiResult
    # Returned by {#errors} for an aborted transaction so callers can iterate
    # the value without a nil check. Frozen because it is shared across every
    # aborted result.
    NO_ERRORS = [].freeze

    # @return [Array, nil] The raw return values from the Database commands,
    #   or nil when the transaction was aborted before EXEC ran
    attr_reader :results

    # Creates a new MultiResult instance.
    #
    # @param results [Array, nil] The raw results from Database commands.
    #   Exception objects in the array indicate command failures. nil means
    #   the transaction was discarded rather than executed (see {#aborted?}).
    def initialize(results)
      @results = results
    end

    # Whether the transaction was discarded instead of executed.
    #
    # redis-rb returns nil from #multi when EXEC is aborted, which happens
    # when a WATCH-guarded transaction detects that a watched key changed
    # under it. An aborted transaction applied none of its commands, so it
    # reports no errors ({#errors} is empty) but is also not successful --
    # callers should retry rather than treat it as a no-op success.
    #
    # @return [Boolean] true if no command results were returned
    def aborted?
      results.nil?
    end

    # Returns all Exception objects from the results array.
    #
    # This method is memoized for performance when called multiple times
    # on the same MultiResult instance.
    #
    # @return [Array<Exception>] Array of exceptions that occurred during
    #   execution; always empty for an aborted transaction, which ran no
    #   commands and therefore produced no per-command failures
    def errors
      return NO_ERRORS if aborted?

      @errors ||= results.select { |ret| ret.is_a?(Exception) }
    end

    # Checks if any errors occurred during execution.
    #
    # An aborted transaction reports false here -- it failed, but not because
    # a command errored. Use {#successful?} to test the overall outcome.
    #
    # @return [Boolean] true if at least one command failed, false otherwise
    def errors?
      !errors.empty?
    end

    # Checks if all commands completed successfully (no exceptions).
    #
    # This is the primary method for determining if a multi-command
    # operation completed without errors.
    #
    # @return [Boolean] true if the transaction ran and no exceptions are in
    #   results, false otherwise (including an aborted transaction)
    def successful?
      !aborted? && errors.empty?
    end
    alias success? successful?
    alias areyouhappynow? successful?

    # Returns a tuple representing the result of the operation.
    #
    # @return [Array] A tuple containing the success status and the raw results.
    #   The success status is a boolean indicating if all commands succeeded.
    #   The raw results is an array of return values from the Database commands,
    #   or nil for an aborted transaction.
    #
    # @example
    #   [true, ["OK", true, 1]]
    #
    def tuple
      [successful?, results]
    end
    alias to_a tuple

    # Returns the number of results in the multi-operation.
    #
    # @return [Integer] The number of individual command results returned;
    #   0 for an aborted transaction
    def size
      return 0 if aborted?

      results.size
    end

    # Returns a hash representation of the result.
    #
    # @return [Hash] Hash with :success and :results keys
    def to_h
      { success: successful?, results: results }
    end
  end
end
