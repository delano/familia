# lib/familia/multi_result.rb

# Represents the result of a Valkey/Redis transaction operation.
#
# This class encapsulates the outcome of a Database transaction,
# providing access to both the success status and the individual
# command results returned by the transaction.
#
# @attr_reader success [Boolean] Indicates whether all commands
#   in the transaction completed successfully.
# @attr_reader results [Array<String>] Array of return values
#   from the Database commands executed in the transaction.
#
# @example Creating a MultiResult instance
#   result = MultiResult.new(true, ["OK", "OK"])
#
# @example Checking transaction success
#   if result.successful?
#     puts "Transaction completed successfully"
#   else
#     puts "Transaction failed"
#   end
#
# @example Accessing individual command results
#   result.results.each_with_index do |value, index|
#     puts "Command #{index + 1} returned: #{value}"
#   end
#
class MultiResult
  # @return [Boolean] true if all commands in the transaction succeeded,
  #   false otherwise
  attr_reader :success

  # @return [Array<String>] The raw return values from the Database commands
  attr_reader :results

  # Creates a new MultiResult instance.
  #
  # @param success [Boolean] Whether all commands succeeded
  # @param results [Array<String>] The raw results from Database commands
  def initialize(success, results)
    @success = success
    @results = results
  end

  # Returns a tuple representing the result of the transaction.
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
  # @return [Integer] The number of individual command results returned by the transaction.
  def size
    results.size
  end

  def to_h
    { success: successful?, results: results }
  end

  # Convenient method to check if the commit was successful.
  #
  # @return [Boolean] true if all commands succeeded, false otherwise
  def successful?
    @success
  end
  alias success? successful?
end
