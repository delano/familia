# lib/multi_result.rb
#
# frozen_string_literal: true

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
# @attr_reader results [Array] Array of return values from the Database commands.
#   Values can be strings, integers, booleans, or Exception objects for failed commands.
#
# @example Creating a MultiResult instance
#   result = MultiResult.new(["OK", "OK", 1])
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
class MultiResult
  # @return [Array] The raw return values from the Database commands
  attr_reader :results

  # Creates a new MultiResult instance.
  #
  # @param results [Array] The raw results from Database commands.
  #   Exception objects in the array indicate command failures.
  def initialize(results)
    @results = results
  end

  # Returns all Exception objects from the results array.
  #
  # This method is memoized for performance when called multiple times
  # on the same MultiResult instance.
  #
  # @return [Array<Exception>] Array of exceptions that occurred during execution
  def errors
    @errors ||= results.select { |ret| ret.is_a?(Exception) }
  end

  # Checks if any errors occurred during execution.
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
  # @return [Boolean] true if no exceptions in results, false otherwise
  def successful?
    errors.empty?
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
  # @return [Integer] The number of individual command results returned
  def size
    results.size
  end

  # Returns a hash representation of the result.
  #
  # @return [Hash] Hash with :success and :results keys
  def to_h
    { success: successful?, results: results }
  end
end
