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
  # A multi-command operation has three possible outcomes:
  #
  # 1. **Committed cleanly** -- every queued command returned a value.
  # 2. **Committed with errors** -- the commands ran, but one or more returned
  #    an Exception object. Redis returns failed commands inside a transaction
  #    as exception objects rather than raising them, so the remaining commands
  #    still execute. {#errors} collects them.
  # 3. **Aborted** -- EXEC was discarded and no command ran at all. This is the
  #    documented outcome of a WATCH-guarded transaction whose watched key was
  #    modified by another client; redis-rb signals it by returning nil instead
  #    of an array. See {#aborted?}.
  #
  # An aborted operation is a failure, but not an *error* in the sense of (2):
  # no command ran, so there is nothing for {#errors} to report. {#successful?}
  # is the method to test for the overall outcome; {#errors?} answers the
  # narrower question of whether any individual command failed.
  #
  # {#results} is always an Array -- an aborted operation reports an empty one
  # rather than nil, so callers can index and iterate it unconditionally.
  # Use {#aborted?} to tell an abort apart from an operation that committed
  # zero commands.
  #
  # @attr_reader results [Array] Array of return values from the Database commands.
  #   Values can be strings, integers, booleans, or Exception objects for failed
  #   commands. Empty when the operation queued no commands or was aborted.
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
  # @example Distinguishing an abort from a clean commit
  #   if result.aborted?
  #     retry_the_transaction   # a watched key changed; nothing was applied
  #   elsif result.errors?
  #     report(result.errors)   # the commands ran; some of them failed
  #   end
  #
  class MultiResult
    # @return [Array] The raw return values from the Database commands. Always
    #   an Array; empty for an aborted operation
    attr_reader :results

    # Creates a new MultiResult instance.
    #
    # @param results [Array, nil] The raw results from Database commands.
    #   Exception objects in the array indicate command failures. nil means
    #   the transaction was discarded rather than executed, and is normalized
    #   to an empty array with {#aborted?} recording the distinction.
    def initialize(results)
      @aborted = results.nil?
      @results = results || []
    end

    # Whether the operation was discarded instead of executed.
    #
    # redis-rb returns nil from #multi when EXEC is aborted, which happens when
    # a WATCH-guarded transaction detects that a watched key changed under it.
    # An aborted transaction applied none of its commands, so it reports no
    # errors ({#errors} is empty) but is also not successful -- callers should
    # retry rather than treat it as a no-op success.
    #
    # This is the only way to distinguish an abort from an operation that
    # committed zero commands, since both report an empty {#results}.
    #
    # @return [Boolean] true if EXEC was discarded before any command ran
    def aborted?
      @aborted
    end

    # Returns all Exception objects from the results array.
    #
    # This method is memoized for performance when called multiple times
    # on the same MultiResult instance. The returned array is frozen: it is
    # derived state backing that memo, not a collection for callers to modify.
    #
    # @return [Array<Exception>] Frozen array of exceptions that occurred
    #   during execution; always empty for an aborted operation, which ran no
    #   commands and therefore produced no per-command failures
    def errors
      @errors ||= results.grep(Exception).freeze
    end

    # Checks if any individual command failed.
    #
    # An aborted operation reports false here -- it failed, but not because a
    # command errored. Use {#successful?} to test the overall outcome.
    #
    # @return [Boolean] true if at least one command returned an Exception
    def errors?
      !errors.empty?
    end

    # Checks if the operation ran and all commands completed successfully.
    #
    # This is the primary method for determining if a multi-command
    # operation completed without errors.
    #
    # @return [Boolean] true if the operation ran and no exceptions are in
    #   results, false otherwise (including an aborted operation)
    def successful?
      !aborted? && errors.empty?
    end
    alias success? successful?
    alias areyouhappynow? successful?

    # Returns a tuple representing the result of the operation.
    #
    # @return [Array] A tuple containing the success status and the raw results.
    #   The success status is a boolean indicating if all commands succeeded.
    #   The raw results is an array of return values from the Database commands.
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
    #   0 for an aborted operation
    def size
      results.size
    end

    # Returns a hash representation of the result.
    #
    # Includes :aborted so a failed result is self-describing -- otherwise a
    # dumped abort is indistinguishable from a failure whose errors went
    # missing.
    #
    # @return [Hash] Hash with :success, :aborted, and :results keys
    def to_h
      { success: successful?, aborted: aborted?, results: results }
    end

    # Returns a summary of the outcome for logging and debugging.
    #
    # Deliberately omits the command return values: they routinely carry field
    # values read back out of the database, which have no business landing in
    # a log line or an exception trace by default. Reach for {#results} when
    # the values are what you actually want.
    #
    # @return [String] e.g. +#<Familia::MultiResult aborted size=0>+
    def inspect
      "#<#{self.class.name} #{outcome} size=#{size}>"
    end

    private

    # One-word summary of which of the three outcomes this result represents.
    #
    # @return [String] 'aborted', 'errors=N', or 'ok'
    def outcome
      return 'aborted' if aborted?
      return "errors=#{errors.size}" if errors?

      'ok'
    end
  end
end
