# lib/familia/utils.rb
#
# frozen_string_literal: true

module Familia
  # Family-related utility methods
  #
  module Utils
    using Familia::Refinements::TimeLiterals

    # Future-aware success check for Redis command return values.
    #
    # Redis commands like HSET return 0 (updated existing) or 1 (created new).
    # Both are success states. Inside a pipeline or transaction, the return
    # value is a Redis::Future which cannot be inspected until the block
    # completes.
    #
    # @param ret [Integer, Redis::Future] The return value from a Redis command
    # @return [Boolean, Redis::Future] true/false for concrete values,
    #   passthrough for Futures
    #
    # @example Normal usage
    #   ret = dbclient.hset(key, field, value)
    #   Familia.success?(ret)  #=> true (for 0 or 1)
    #
    # @example Inside pipeline
    #   pipelined do
    #     ret = dbclient.hset(key, field, value)
    #     Familia.success?(ret)  #=> Redis::Future (passthrough)
    #   end
    #
    def success?(ret)
      ret.is_a?(Redis::Future) ? ret : (ret.zero? || ret.positive?)
    end

    # Future-aware positive check for Redis command return values.
    #
    # For commands where 0 means "nothing happened" and positive means
    # "something happened" (e.g., EXISTS, DEL, LINSERT, TTL checks).
    #
    # @param ret [Integer, Redis::Future] The return value from a Redis command
    # @return [Boolean, Redis::Future] true/false for concrete values,
    #   passthrough for Futures
    #
    # @example Check if key exists
    #   ret = dbclient.exists(key)
    #   Familia.positive?(ret)  #=> true if key exists
    #
    # @example Check TTL inside pipeline
    #   pipelined do
    #     ret = dbclient.ttl(key)
    #     Familia.positive?(ret)  #=> Redis::Future (passthrough)
    #   end
    #
    def positive?(ret)
      ret.is_a?(Redis::Future) ? ret : ret.positive?
    end

    # Future-aware conversion of a Redis command reply.
    #
    # Yields a concrete reply to the block and returns the block's result.
    # Returns a Redis::Future untouched: inside a pipeline or transaction the
    # reply is not available until the block completes, so the conversion
    # cannot run. The Future then resolves to the reply as redis-rb returns
    # it, without the block's conversion. See docs/reference/transaction_safety.md.
    #
    # @param ret [Object, Redis::Future] The return value from a Redis command
    # @yieldparam reply [Object] The concrete reply
    # @return [Object, Redis::Future] The block's result for concrete values,
    #   passthrough for Futures
    #
    # @example Deserialize a reply
    #   Familia.transform_reply(dbclient.hvals(key)) do |vals|
    #     vals.map { |v| deserialize_value(v) }
    #   end
    #
    def transform_reply(ret)
      ret.is_a?(Redis::Future) ? ret : yield(ret)
    end

    # Whether the current fiber is inside a Familia transaction or pipeline
    # block. Commands issued there are queued, and each returns a
    # Redis::Future instead of its reply.
    #
    # @return [Boolean]
    #
    def transaction_or_pipeline?
      !(Fiber[:familia_transaction].nil? && Fiber[:familia_pipeline].nil?)
    end

    # Refuses to run an operation that needs command replies inside a
    # transaction or pipeline block.
    #
    # Some methods must read a reply before they can finish: they branch on
    # it, raise from it, issue follow-up commands based on it, iterate over
    # it, or load records from it. Inside a transaction or pipeline every
    # reply is a Redis::Future until the block completes, so such a method
    # would act on a placeholder. It raises instead, before queueing
    # anything.
    #
    # A method that takes its connection as an argument passes it as
    # +conn+. The check then looks at that connection instead of the current
    # fiber: a transaction or pipeline connection (a MULTI or pipeline
    # block's yield, or Familia.dbclient inside a Familia block) queues its
    # commands, while a separate plain client answers even inside a block.
    #
    # @param operation [String] The method name for the error message,
    #   such as "HashKey#fetch"
    # @param conn [Redis, Redis::PipelinedConnection, nil] the connection
    #   the operation will issue its commands on, when it takes one
    # @return [void]
    # @raise [Familia::OperationModeError] without +conn+, inside a
    #   transaction or pipeline; with +conn+, only when +conn+ is a
    #   transaction or pipeline connection
    #
    def assert_replies_available!(operation, conn: nil)
      queued = conn.nil? ? transaction_or_pipeline? : conn.is_a?(Redis::PipelinedConnection)
      return unless queued

      raise Familia::OperationModeError,
            "#{operation} cannot run inside a transaction or pipeline: it needs " \
            'command replies, which are Redis::Future objects until the block ' \
            'completes. Call it outside the block.'
    end

    # Detects the legacy JSON-encoded string format written by pre-2.10.0
    # reference collections (e.g. unique_index hashkeys stored `"\"u1\""`
    # instead of the raw `"u1"`).
    #
    # This is the single source of truth for the format check: the read path
    # (DataType::Serialization#strip_legacy_json_encoding) strips such values,
    # and the index introspection layer (IndexDescriptor#stale_format?) samples
    # for them to flag indexes that need a rebuild. Side-effect free.
    #
    # @param val [Object] the raw stored value
    # @return [Boolean] true when val is a JSON-encoded string identifier
    def legacy_json_encoded?(val)
      val.is_a?(String) && val.length > 2 && val.start_with?('"') && val.end_with?('"')
    end

    # Returns +str+ in the encoding redis-client gives a key or member with
    # the same bytes: UTF-8 when the bytes are valid UTF-8, BINARY otherwise.
    # (redis-client labels each bulk string it reads as UTF-8 and relabels it
    # BINARY unless it is valid.) The bytes are not changed.
    #
    # Every key {#join} builds goes through here, so a key is one String
    # value wherever it comes from. Before, a key built from a UTF-8
    # identifier with invalid bytes was UTF-8 while the same key built from
    # the member read back was BINARY, and the two were neither == nor equal
    # as Hash keys.
    #
    # @param str [#to_s] key, key part or identifier
    # @return [String] a UTF-8 String when the bytes are valid UTF-8, else a
    #   BINARY String; +str+ itself when it is already a valid UTF-8 String
    def normalize_key_encoding(str)
      text = str.to_s
      text = text.dup.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
      text.valid_encoding? ? text : text.b
    end

    # Joins array elements with Familia delimiter
    #
    # The result has the encoding {#normalize_key_encoding} gives it: UTF-8
    # when its bytes are valid UTF-8, BINARY otherwise. So a key built from
    # an identifier is == to the same key read back from the server, whatever
    # encoding the identifier was given in.
    #
    # When the parts carry non-ASCII bytes in incompatible encodings, such as
    # a non-ASCII class prefix (e.g. 'équipe') with an identifier that
    # redis-client returned as BINARY because it is not valid UTF-8, the
    # parts are joined as bytes.
    #
    # @param val [Array] elements to join
    # @return [String] joined string
    def join(*val)
      parts = val.compact
      key = begin
        parts.join(Familia.delim)
      rescue Encoding::CompatibilityError
        parts.flatten.map { |part| part.to_s.b }.join(Familia.delim.to_s.b)
      end
      normalize_key_encoding(key)
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

    # Glob pattern characters escaped by {#escape_glob}: the wildcards, both
    # brackets and the escape character itself. The documented patterns use
    # the caret and the hyphen only inside brackets (h[^e]llo, h[a-b]llo),
    # and no bracket expression can open once every opening bracket is
    # escaped, so those two need no escape.
    GLOB_SPECIAL_CHARACTERS = /[*?\[\]\\]/

    # Escapes +str+ so that it matches only itself inside a key pattern.
    #
    # Use it for every literal part of a KEYS or SCAN MATCH pattern that is
    # built from data (identifiers, field values, prefixes, suffixes, the
    # delimiter) and leave only the intended wildcards unescaped. The Valkey
    # and Redis KEYS documentation (https://valkey.io/commands/keys/ and
    # https://redis.io/docs/latest/commands/keys/) both state: "Use `\` to
    # escape special characters if you want to match them verbatim." The
    # Valkey SCAN documentation (https://valkey.io/commands/scan/) describes
    # the MATCH option as a glob-style pattern that works "similarly to the
    # behavior of the `KEYS` command".
    #
    # The escaping works on the bytes: it puts an ASCII backslash before
    # each ASCII special character and leaves every other byte as it is. So
    # a String that is not valid in its encoding, such as an identifier with
    # invalid UTF-8 bytes or binary data, is escaped without raising, and
    # the result keeps the encoding of the input.
    #
    # @param str [#to_s] the literal text
    # @return [String] the text with each glob special character escaped
    #
    # @example
    #   Familia.escape_glob('c-*')                      #=> "c-\\*"
    #   "#{Familia.escape_glob('company:c-*:dept:')}*"  #=> "company:c-\\*:dept:*"
    #
    def escape_glob(str)
      text = str.to_s
      text.b.gsub(GLOB_SPECIAL_CHARACTERS) { |char| "\\#{char}" }.force_encoding(text.encoding)
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

    # Returns the current time in microseconds.
    # This is used to measure the duration of Database commands.
    #
    # Alias: now_in_microseconds
    #
    # @return [Integer] The current time in microseconds.
    def now_in_μs
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    end
    alias now_in_microseconds now_in_μs

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
