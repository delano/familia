# lib/familia/multi_result.rb

# The magical MultiResult, keeper of Redis's deepest secrets!
#
# This quirky little class wraps up the outcome of a Redis "transaction"
# (or as I like to call it, a "Redis dance party") with a bow made of
# pure Ruby delight. It knows if your commands were successful and
# keeps the results safe in its pocket dimension.
#
# @attr_reader success [Boolean] The golden ticket! True if all your
#   Redis wishes came true in the transaction.
# @attr_reader results [Array<String>] A mystical array of return values,
#   each one a whisper from the Redis gods.
#
# @example Summoning a MultiResult from the void
#   result = MultiResult.new(true, ["OK", "OK"])
#
# @example Divining the success of your Redis ritual
#   if result.successful?
#     puts "Huzzah! The Redis spirits smile upon you!"
#   else
#     puts "Alas! The Redis gremlins have conspired against us!"
#   end
#
# @example Peering into the raw essence of results
#   result.results.each_with_index do |value, index|
#     puts "Command #{index + 1} whispered back: #{value}"
#   end
#
class MultiResult
  # @return [Boolean] true if all commands in the transaction succeeded,
  #   false otherwise
  attr_reader :success

  # @return [Array<String>] The raw return values from the Redis commands
  attr_reader :results

  # Creates a new MultiResult instance.
  #
  # @param success [Boolean] Whether all commands succeeded
  # @param results [Array<String>] The raw results from Redis commands
  def initialize(success, results)
    @success = success
    @results = results
  end

  # Returns a tuple representing the result of the transaction.
  #
  # @return [Array] A tuple containing the success status and the raw results.
  #   The success status is a boolean indicating if all commands succeeded.
  #   The raw results is an array of return values from the Redis commands.
  #
  # @example
  #   [true, ["OK", true, 1]]
  #
  def tuple
    [successful?, results]
  end
  alias to_a tuple

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
# End of MultiResult class
