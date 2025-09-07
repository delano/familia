# lib/familia/utils.rb

module Familia

  # Family-related utility methods
  #
  module Utils

    using Familia::Refinements::TimeUtils

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
    # @param name [Time] time object (default: current time)
    # @return [Float] time in seconds since epoch
    def now(name = Time.now)
      name.utc.to_f
    end

    # A quantized timestamp
    #
    # @param quantum [Integer] The time quantum in seconds (default: 10 minutes).
    # @param pattern [String, nil] The strftime pattern to format the timestamp.
    # @param time [Integer, Float, Time, nil] A specific time to quantize (default: current time).
    # @return [Integer, String] A unix timestamp or formatted timestamp string.
    #
    # @example
    #   Familia.qstamp  # Returns an integer timestamp rounded to the nearest 10 minutes
    #   Familia.qstamp(1.hour)  # Uses 1 hour quantum
    #   Familia.qstamp(10.minutes, pattern: '%H:%M')  # Returns a formatted string like "12:30"
    #   Familia.qstamp(10.minutes, time: 1302468980)  # Quantizes the given Unix timestamp
    #   Familia.qstamp(10.minutes, time: Time.now)  # Quantizes the given Time object
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

    # This method determines the appropriate transformation to apply based on
    # the class of the input argument.
    #
    # @param [Object] value_to_distinguish The value to be processed. Keep in
    #   mind that all data is stored as a string so whatever the type
    #   of the value, it will be converted to a string.
    # @param [Boolean] strict_values Whether to enforce strict value handling.
    #   Defaults to true.
    # @return [String, nil] The processed value as a string or nil for unsupported
    #   classes.
    #
    # The method uses a case statement to handle different classes:
    # - For `Symbol`, `String`, `Integer`, and `Float` classes, it traces the
    #   operation and converts the value to a string.
    # - For `Familia::Horreum` class, it traces the operation and returns the
    #   identifier of the value.
    # - For `TrueClass`, `FalseClass`, and `NilClass`, it traces the operation and
    #   converts the value to a string ("true", "false", or "").
    # - For any other class, it traces the operation and returns nil.
    #
    # Alternative names for `value_to_distinguish` could be `input_value`, `value`,
    # or `object`.
    #
    def distinguisher(value_to_distinguish, strict_values: true)
      case value_to_distinguish
      when ::Symbol, ::String, ::Integer, ::Float
        Familia.trace :TOREDIS_DISTINGUISHER, dbclient, 'string', caller(1..1) if Familia.debug?

        # Symbols and numerics are naturally serializable to strings
        # so it's a relatively low risk operation.
        value_to_distinguish.to_s

      when ::TrueClass, ::FalseClass, ::NilClass
        Familia.trace :TOREDIS_DISTINGUISHER, dbclient, 'true/false/nil', caller(1..1) if Familia.debug?

        # TrueClass, FalseClass, and NilClass are considered high risk because their
        # original types cannot be reliably determined from their serialized string
        # representations. This can lead to unexpected behavior during deserialization.
        # For instance, a TrueClass value serialized as "true" might be deserialized as
        # a String, causing application errors. Even more problematic, a NilClass value
        # serialized as an empty string makes it impossible to distinguish between a
        # nil value and an empty string upon deserialization. Such scenarios can result
        # in subtle, hard-to-diagnose bugs. To mitigate these risks, we raise an
        # exception when encountering these types unless the strict_values option is
        # explicitly set to false.
        #
        raise Familia::HighRiskFactor, value_to_distinguish if strict_values

        value_to_distinguish.to_s #=> "true", "false", ""

      when Familia::Base, Class
        Familia.trace :TOREDIS_DISTINGUISHER, dbclient, 'base', caller(1..1) if Familia.debug?

        # When called with a class we simply transform it to its name. For
        # instances of Familia class, we store the identifier.
        if value_to_distinguish.is_a?(Class)
          value_to_distinguish.name
        else
          value_to_distinguish.identifier
        end

      else
        Familia.trace :TOREDIS_DISTINGUISHER, dbclient, "else1 #{strict_values}", caller(1..1) if Familia.debug?

        if value_to_distinguish.class.ancestors.member?(Familia::Base)
          Familia.trace :TOREDIS_DISTINGUISHER, dbclient, 'isabase', caller(1..1) if Familia.debug?

          value_to_distinguish.identifier

        else
          Familia.trace :TOREDIS_DISTINGUISHER, dbclient, "else2 #{strict_values}", caller(1..1) if Familia.debug?
          raise Familia::HighRiskFactor, value_to_distinguish if strict_values

          nil
        end
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
