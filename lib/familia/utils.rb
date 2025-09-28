# lib/familia/utils.rb

module Familia
  # Family-related utility methods
  #
  module Utils
    using Familia::Refinements::TimeLiterals

    # Joins array elements with Familia delimiter
    # @param val [Array] elements to join
    # @return [String] joined string
    def join(*val)
      val.compact.join(Familia.delim)
    end

    # Splits a string using Familia delimiter
    # @param val [String] string to split
    # @return [Array] split elements
    def split(val)
      val.split(Familia.delim)
    end

    # Creates a dbkey from given values
    # @param val [Array] elements to join for the key
    # @return [String] dbkey
    def dbkey(*val)
      join(*val)
    end

    # Gets server ID without DB component for pool identification
    def serverid(uri)
      # Create a copy of URI without DB for server identification
      uri = uri.dup
      uri.db = nil
      uri.serverid
    end

    # Returns current time in UTC as a float
    # @param current_time [Time] time object (default: current time)
    # @return [Float] time in seconds since epoch
    def now(current_time = Time.now)
      current_time.utc.to_f
    end

    # A quantized timestamp
    #
    # @param quantum [Integer] The time quantum in seconds (default: 10 minutes).
    # @param pattern [String, nil] The strftime pattern to format the timestamp.
    # @param time [Integer, Float, Time, nil] A specific time to quantize (default: current time).
    # @return [Integer, String] A unix timestamp or formatted timestamp string.
    #
    # @example Familia.qstamp  # Returns an integer timestamp rounded to the nearest 10 minutes
    #   Familia.qstamp(1.hour)  # Uses 1 hour quantum
    #   Familia.qstamp(10.minutes, pattern: '%H:%M')  # Returns a formatted string like "12:30"
    #   Familia.qstamp(10.minutes, time: 1302468980)  # Quantizes the given Unix timestamp
    #   Familia.qstamp(10.minutes, time: Familia.now)  # Quantizes the given Time object
    #   Familia.qstamp(10.minutes, pattern: '%H:%M', time: 1302468980)  # Formats a specific time
    #
    def qstamp(quantum = 10.minutes, pattern: nil, time: nil)
      time ||= Familia.now
      time = time.to_f if time.is_a?(Time)

      rounded = time - (time % quantum)

      if pattern
        Time.at(rounded).utc.strftime(pattern)
      else
        Time.at(rounded).utc.to_i
      end
    end

    # Converts an absolute file path to a path relative to the current working
    # directory. This simplifies logging and error reporting by showing
    # only the relevant parts of file paths instead of lengthy absolute paths.
    #
    # @param filepath [String, Pathname] The file path to convert
    # @return [Pathname, String, nil] A relative path from current directory,
    #   basename if path goes outside current directory, or nil if filepath is nil
    #
    # @example Using current directory as base
    #   Utils.pretty_path("/home/dev/project/lib/config.rb") # => "lib/config.rb"
    #
    # @example Path outside current directory
    #   Utils.pretty_path("/etc/hosts") # => "hosts"
    #
    # @example Nil input
    #   Utils.pretty_path(nil) # => nil
    #
    # @see Pathname#relative_path_from Ruby standard library documentation
    def pretty_path(filepath)
      return nil if filepath.nil?

      basepath = Dir.pwd
      relative_path = Pathname.new(filepath).relative_path_from(basepath)
      if relative_path.to_s.start_with?('..')
        File.basename(filepath)
      else
        relative_path
      end
    end

    # Formats a stack trace with pretty file paths for improved readability
    #
    # @param limit [Integer] Maximum number of stack frames to include (default: 3)
    # @return [String] Formatted stack trace with relative paths joined by newlines
    #
    # @example
    #   Utils.pretty_stack(limit: 10)
    #   # => "lib/models/user.rb:25:in `save'\n lib/controllers/app.rb:45:in `create'"
    def pretty_stack(skip: 1, limit: 5)
      caller(skip..(skip + limit + 1)).first(limit).map { |frame| pretty_path(frame) }.join("\n")
    end
  end
end
