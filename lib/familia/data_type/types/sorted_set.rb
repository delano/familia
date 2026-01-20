# lib/familia/data_type/types/sorted_set.rb
#
# frozen_string_literal: true

module Familia
  class SortedSet < DataType
    # Returns the number of elements in the sorted set
    # @return [Integer] number of elements
    def element_count
      dbclient.zcard dbkey
    end
    alias size element_count
    alias length element_count
    alias count element_count

    def empty?
      element_count.zero?
    end

    # Adds a new element to the sorted set with the current timestamp as the
    # score.
    #
    # This method provides a convenient way to add elements to the sorted set
    # without explicitly specifying a score. It uses the current Unix timestamp
    # as the score, which effectively sorts elements by their insertion time.
    #
    # @param val [Object] The value to be added to the sorted set.
    # @return [Integer] Returns 1 if the element is new and added, 0 if the
    #   element already existed and the score was updated.
    #
    # @example sorted_set << "new_element"
    #
    # @note This is a non-standard operation for sorted sets as it doesn't allow
    #   specifying a custom score. Use `add` or `[]=` for more control.
    #
    def <<(val)
      add(val)
    end

    # NOTE: The argument order is the reverse of #add. We do this to
    # more naturally align with how the [] and []= methods are used.
    #
    # e.g.
    #     obj.metrics[VALUE] = SCORE
    #     obj.metrics[VALUE]  # => SCORE
    #
    def []=(val, score)
      add val, score
    end

    # Adds an element to the sorted set with an optional score and ZADD options.
    #
    # This method supports Redis ZADD options for conditional adds and updates:
    # - **NX**: Only add new elements (don't update existing)
    # - **XX**: Only update existing elements (don't add new)
    # - **GT**: Only update if new score > current score
    # - **LT**: Only update if new score < current score
    # - **CH**: Return changed count (new + updated) instead of just new count
    #
    # @param val [Object] The value to add to the sorted set
    # @param score [Numeric, nil] The score for ranking (defaults to current timestamp)
    # @param nx [Boolean] Only add new elements, don't update existing (default: false)
    # @param xx [Boolean] Only update existing elements, don't add new (default: false)
    # @param gt [Boolean] Only update if new score > current score (default: false)
    # @param lt [Boolean] Only update if new score < current score (default: false)
    # @param ch [Boolean] Return changed count instead of added count (default: false)
    #
    # @return [Boolean] Returns the return value from the redis gem's ZADD
    #   command. Returns true if element was added or changed (with CH option),
    #   false if element score was updated without change tracking or no
    #   operation occurred due to option constraints (NX, XX, GT, LT).
    #
    # @raise [ArgumentError] If mutually exclusive options are specified together
    #   (NX+XX, GT+LT, NX+GT, NX+LT)
    #
    # @example Add new element with timestamp
    #   metrics.add('pageview', Time.now.to_f)  #=> true
    #
    # @example Preserve original timestamp on subsequent saves
    #   index.add(email, Time.now.to_f, nx: true)  #=> true
    #   index.add(email, Time.now.to_f, nx: true)  #=> false (unchanged)
    #
    # @example Update timestamp only for existing entries
    #   index.add(email, Time.now.to_f, xx: true)  #=> false (if doesn't exist)
    #
    # @example Only update if new score is higher (leaderboard)
    #   scores.add(player, 1000, gt: true)  #=> true (new entry)
    #   scores.add(player, 1500, gt: true)  #=> false (updated)
    #   scores.add(player, 1200, gt: true)  #=> false (not updated, score lower)
    #
    # @example Track total changes for analytics
    #   changed = metrics.add(user, score, ch: true)  #=> true (new or updated)
    #
    # @example Combined options: only update existing, only if score increases
    #   index.add(key, new_score, xx: true, gt: true)
    #
    # @note GT and LT options do NOT prevent adding new elements, they only
    #   affect update behavior for existing elements.
    #
    # @note Default behavior (no options) adds new elements and updates existing
    #   ones unconditionally, matching standard Redis ZADD semantics.
    #
    # @note INCR option is not supported. Use the increment method for ZINCRBY operations.
    #
    def add(val, score = nil, nx: false, xx: false, gt: false, lt: false, ch: false)
      score ||= Familia.now

      # Validate mutual exclusivity
      validate_zadd_options!(nx: nx, xx: xx, gt: gt, lt: lt)

      # Build options hash for redis gem
      opts = {}
      opts[:nx] = true if nx
      opts[:xx] = true if xx
      opts[:gt] = true if gt
      opts[:lt] = true if lt
      opts[:ch] = true if ch

      # Pass options to ZADD
      ret = if opts.empty?
        dbclient.zadd(dbkey, score, serialize_value(val))
      else
        dbclient.zadd(dbkey, score, serialize_value(val), **opts)
      end

      update_expiration
      ret
    end
    alias add_element add

    def score(val)
      ret = dbclient.zscore dbkey, serialize_value(val)
      ret&.to_f
    end
    alias [] score

    def member?(val)
      Familia.trace :MEMBER, nil, "#{val}<#{val.class}>" if Familia.debug?
      !rank(val).nil?
    end
    alias include? member?

    # rank of member +v+ when ordered lowest to highest (starts at 0)
    def rank(v)
      ret = dbclient.zrank dbkey, serialize_value(v)
      ret&.to_i
    end

    # rank of member +v+ when ordered highest to lowest (starts at 0)
    def revrank(v)
      ret = dbclient.zrevrank dbkey, serialize_value(v)
      ret&.to_i
    end

    def members(count = -1, opts = {})
      count -= 1 if count.positive?
      elements = membersraw count, opts
      deserialize_values(*elements)
    end
    alias to_a members
    alias all members

    def membersraw(count = -1, opts = {})
      count -= 1 if count.positive?
      rangeraw 0, count, opts
    end

    def revmembers(count = -1, opts = {})
      count -= 1 if count.positive?
      elements = revmembersraw count, opts
      deserialize_values(*elements)
    end

    def revmembersraw(count = -1, opts = {})
      count -= 1 if count.positive?
      revrangeraw 0, count, opts
    end

    def each(&)
      members.each(&)
    end

    def each_with_index(&)
      members.each_with_index(&)
    end

    def collect(&)
      members.collect(&)
    end

    def select(&)
      members.select(&)
    end

    def eachraw(&)
      membersraw.each(&)
    end

    def eachraw_with_index(&)
      membersraw.each_with_index(&)
    end

    def collectraw(&)
      membersraw.collect(&)
    end

    def selectraw(&)
      membersraw.select(&)
    end

    def range(sidx, eidx, opts = {})
      echo :range, Familia.pretty_stack(limit: 1) if Familia.debug
      elements = rangeraw(sidx, eidx, opts)
      deserialize_values(*elements)
    end

    def rangeraw(sidx, eidx, opts = {})
      # NOTE: :withscores (no underscore) is the correct naming for the
      # redis-4.x gem. We pass :withscores through explicitly b/c
      # dbclient.zrange et al only accept that one optional argument.
      # Passing `opts`` through leads to an ArgumentError:
      #
      #   sorted_sets.rb:374:in `zrevrange': wrong number of arguments (given 4, expected 3) (ArgumentError)
      #
      dbclient.zrange(dbkey, sidx, eidx, **opts)
    end

    def revrange(sidx, eidx, opts = {})
      echo :revrange, Familia.pretty_stack(limit: 1) if Familia.debug
      elements = revrangeraw(sidx, eidx, opts)
      deserialize_values(*elements)
    end

    def revrangeraw(sidx, eidx, opts = {})
      dbclient.zrevrange(dbkey, sidx, eidx, **opts)
    end

    # e.g. obj.metrics.rangebyscore (now-12.hours), now, :limit => [0, 10]
    def rangebyscore(sscore, escore, opts = {})
      echo :rangebyscore, Familia.pretty_stack(limit: 1) if Familia.debug
      elements = rangebyscoreraw(sscore, escore, opts)
      deserialize_values(*elements)
    end

    def rangebyscoreraw(sscore, escore, opts = {})
      echo :rangebyscoreraw, Familia.pretty_stack(limit: 1) if Familia.debug
      dbclient.zrangebyscore(dbkey, sscore, escore, **opts)
    end

    # e.g. obj.metrics.revrangebyscore (now-12.hours), now, :limit => [0, 10]
    def revrangebyscore(sscore, escore, opts = {})
      echo :revrangebyscore, Familia.pretty_stack(limit: 1) if Familia.debug
      elements = revrangebyscoreraw(sscore, escore, opts)
      deserialize_values(*elements)
    end

    def revrangebyscoreraw(sscore, escore, opts = {})
      echo :revrangebyscoreraw, Familia.pretty_stack(limit: 1) if Familia.debug
      opts[:with_scores] = true if opts[:withscores]
      dbclient.zrevrangebyscore(dbkey, sscore, escore, opts)
    end

    def remrangebyrank(srank, erank)
      dbclient.zremrangebyrank dbkey, srank, erank
    end

    def remrangebyscore(sscore, escore)
      dbclient.zremrangebyscore dbkey, sscore, escore
    end

    def increment(val, by = 1)
      dbclient.zincrby(dbkey, by, serialize_value(val)).to_i
    end
    alias incr increment
    alias incrby increment

    def decrement(val, by = 1)
      increment val, -by
    end
    alias decr decrement
    alias decrby decrement

    # Removes a member from the sorted set
    # @param value The value to remove from the sorted set
    # @return [Integer] The number of members that were removed (0 or 1)
    def remove_element(value)
      Familia.trace :REMOVE_ELEMENT, nil, "#{value}<#{value.class}>" if Familia.debug?
      dbclient.zrem dbkey, serialize_value(value)
    end
    alias remove remove_element # deprecated

    def at(idx)
      range(idx, idx).first
    end

    # Return the first element in the list. Redis: ZRANGE(0)
    def first
      at(0)
    end

    # Return the last element in the list. Redis: ZRANGE(-1)
    def last
      at(-1)
    end

    # Removes and returns the member(s) with the lowest score(s).
    #
    # @param count [Integer] Number of members to pop (default: 1)
    # @return [Array, nil] Array of [member, score] pairs, or single pair if count=1,
    #   or nil if set is empty
    #
    # @example Pop single lowest-scoring member
    #   zset.popmin  #=> ["member1", 1.0]
    #
    # @example Pop multiple lowest-scoring members
    #   zset.popmin(3)  #=> [["member1", 1.0], ["member2", 2.0], ["member3", 3.0]]
    #
    def popmin(count = 1)
      result = dbclient.zpopmin(dbkey, count)
      return nil if result.nil? || result.empty?

      update_expiration

      if count == 1 && result.is_a?(Array) && result.length == 2 && !result[0].is_a?(Array)
        # Single result: [member, score]
        [deserialize_value(result[0]), result[1].to_f]
      else
        # Multiple results: [[member, score], ...]
        result.map { |member, score| [deserialize_value(member), score.to_f] }
      end
    end

    # Removes and returns the member(s) with the highest score(s).
    #
    # @param count [Integer] Number of members to pop (default: 1)
    # @return [Array, nil] Array of [member, score] pairs, or single pair if count=1,
    #   or nil if set is empty
    #
    # @example Pop single highest-scoring member
    #   zset.popmax  #=> ["member1", 100.0]
    #
    # @example Pop multiple highest-scoring members
    #   zset.popmax(3)  #=> [["member3", 100.0], ["member2", 90.0], ["member1", 80.0]]
    #
    def popmax(count = 1)
      result = dbclient.zpopmax(dbkey, count)
      return nil if result.nil? || result.empty?

      update_expiration

      if count == 1 && result.is_a?(Array) && result.length == 2 && !result[0].is_a?(Array)
        # Single result: [member, score]
        [deserialize_value(result[0]), result[1].to_f]
      else
        # Multiple results: [[member, score], ...]
        result.map { |member, score| [deserialize_value(member), score.to_f] }
      end
    end

    # Counts members within a score range.
    #
    # @param min [Numeric, String] Minimum score (use '-inf' for unbounded)
    # @param max [Numeric, String] Maximum score (use '+inf' for unbounded)
    # @return [Integer] Number of members with scores in the range
    #
    # @example Count members with scores between 10 and 100
    #   zset.score_count(10, 100)  #=> 5
    #
    # @example Count members with scores up to 50
    #   zset.score_count('-inf', 50)  #=> 3
    #
    def score_count(min, max)
      dbclient.zcount(dbkey, min, max)
    end
    alias zcount score_count

    # Gets scores for multiple members at once.
    #
    # @param members [Array<Object>] Members to get scores for
    # @return [Array<Float, nil>] Scores for each member (nil if member doesn't exist)
    #
    # @example Get scores for multiple members
    #   zset.mscore('member1', 'member2', 'member3')  #=> [1.0, 2.0, nil]
    #
    def mscore(*members)
      return [] if members.empty?

      serialized = members.map { |m| serialize_value(m) }
      result = dbclient.zmscore(dbkey, *serialized)
      result.map { |s| s&.to_f }
    end

    # Returns the union of this sorted set with other sorted sets.
    #
    # @param other_sets [Array<SortedSet, String>] Other sorted sets or key names
    # @param weights [Array<Numeric>, nil] Multiplication factors for each set's scores
    # @param aggregate [Symbol, nil] How to aggregate scores (:sum, :min, :max)
    # @return [Array] Array of members (or [member, score] pairs with withscores)
    #
    # @example Union of two sorted sets
    #   zset.union(other_zset)  #=> ["member1", "member2", "member3"]
    #
    # @example Union with weighted scores
    #   zset.union(other_zset, weights: [1, 2])
    #
    # @example Union with score aggregation
    #   zset.union(other_zset, aggregate: :max)
    #
    def union(*other_sets, weights: nil, aggregate: nil, withscores: false)
      keys = [dbkey] + resolve_set_keys(other_sets)
      opts = build_set_operation_opts(weights: weights, aggregate: aggregate, withscores: withscores)

      result = dbclient.zunion(*keys, **opts)
      process_set_operation_result(result, withscores: withscores)
    end

    # Returns the intersection of this sorted set with other sorted sets.
    #
    # @param other_sets [Array<SortedSet, String>] Other sorted sets or key names
    # @param weights [Array<Numeric>, nil] Multiplication factors for each set's scores
    # @param aggregate [Symbol, nil] How to aggregate scores (:sum, :min, :max)
    # @return [Array] Array of members (or [member, score] pairs with withscores)
    #
    # @example Intersection of two sorted sets
    #   zset.inter(other_zset)  #=> ["common_member"]
    #
    def inter(*other_sets, weights: nil, aggregate: nil, withscores: false)
      keys = [dbkey] + resolve_set_keys(other_sets)
      opts = build_set_operation_opts(weights: weights, aggregate: aggregate, withscores: withscores)

      result = dbclient.zinter(*keys, **opts)
      process_set_operation_result(result, withscores: withscores)
    end

    # Returns members in a lexicographical range (requires all members have same score).
    #
    # @param min [String] Minimum lex value (use '-' for unbounded, '[' or '(' prefix for inclusive/exclusive)
    # @param max [String] Maximum lex value (use '+' for unbounded, '[' or '(' prefix for inclusive/exclusive)
    # @param limit [Array<Integer>, nil] [offset, count] for pagination
    # @return [Array] Members in the lexicographical range
    #
    # @example Get members between 'a' and 'z' (inclusive)
    #   zset.rangebylex('[a', '[z')  #=> ["apple", "banana", "cherry"]
    #
    # @example Get first 10 members starting with 'a'
    #   zset.rangebylex('[a', '(b', limit: [0, 10])
    #
    def rangebylex(min, max, limit: nil)
      args = [dbkey, min, max]
      args.push(:limit, *limit) if limit

      result = dbclient.zrangebylex(*args)
      deserialize_values(*result)
    end

    # Returns members in reverse lexicographical range.
    #
    # @param max [String] Maximum lex value (use '+' for unbounded)
    # @param min [String] Minimum lex value (use '-' for unbounded)
    # @param limit [Array<Integer>, nil] [offset, count] for pagination
    # @return [Array] Members in reverse lexicographical range
    #
    def revrangebylex(max, min, limit: nil)
      args = [dbkey, max, min]
      args.push(:limit, *limit) if limit

      result = dbclient.zrevrangebylex(*args)
      deserialize_values(*result)
    end

    # Removes members in a lexicographical range.
    #
    # @param min [String] Minimum lex value
    # @param max [String] Maximum lex value
    # @return [Integer] Number of members removed
    #
    def remrangebylex(min, max)
      result = dbclient.zremrangebylex(dbkey, min, max)
      update_expiration
      result
    end

    # Counts members in a lexicographical range.
    #
    # @param min [String] Minimum lex value
    # @param max [String] Maximum lex value
    # @return [Integer] Number of members in the range
    #
    def lexcount(min, max)
      dbclient.zlexcount(dbkey, min, max)
    end

    # Returns random member(s) from the sorted set.
    #
    # @param count [Integer, nil] Number of members to return (nil for single member)
    # @param withscores [Boolean] Whether to include scores in result
    # @return [Object, Array, nil] Random member(s), or nil if set is empty
    #
    # @example Get single random member
    #   zset.randmember  #=> "member1"
    #
    # @example Get 3 random members
    #   zset.randmember(3)  #=> ["member1", "member2", "member3"]
    #
    # @example Get random member with score
    #   zset.randmember(1, withscores: true)  #=> [["member1", 1.0]]
    #
    def randmember(count = nil, withscores: false)
      if count.nil?
        result = dbclient.zrandmember(dbkey)
        return nil if result.nil?

        deserialize_value(result)
      else
        result = if withscores
          dbclient.zrandmember(dbkey, count, withscores: true)
        else
          dbclient.zrandmember(dbkey, count)
        end

        return [] if result.nil? || result.empty?

        if withscores
          result.map { |member, score| [deserialize_value(member), score.to_f] }
        else
          deserialize_values(*result)
        end
      end
    end

    # Iterates over members using cursor-based scanning.
    #
    # @param cursor [Integer] Cursor position (0 to start)
    # @param match [String, nil] Pattern to match member names
    # @param count [Integer, nil] Hint for number of elements to return per call
    # @return [Array] [new_cursor, [[member, score], ...]]
    #
    # @example Scan all members
    #   cursor = 0
    #   loop do
    #     cursor, members = zset.scan(cursor)
    #     members.each { |member, score| puts "#{member}: #{score}" }
    #     break if cursor == 0
    #   end
    #
    # @example Scan with pattern matching
    #   cursor, members = zset.scan(0, match: 'user:*', count: 100)
    #
    def scan(cursor = 0, match: nil, count: nil)
      opts = {}
      opts[:match] = match if match
      opts[:count] = count if count

      new_cursor, result = dbclient.zscan(dbkey, cursor, **opts)

      members = result.map { |member, score| [deserialize_value(member), score.to_f] }
      [new_cursor.to_i, members]
    end

    # Stores the union of sorted sets into a destination key.
    #
    # @param destination [String] Destination key name
    # @param other_sets [Array<SortedSet, String>] Other sorted sets or key names
    # @param weights [Array<Numeric>, nil] Multiplication factors for each set's scores
    # @param aggregate [Symbol, nil] How to aggregate scores (:sum, :min, :max)
    # @return [Integer] Number of elements in the resulting sorted set
    #
    def unionstore(destination, *other_sets, weights: nil, aggregate: nil)
      keys = [dbkey] + resolve_set_keys(other_sets)
      opts = build_set_operation_opts(weights: weights, aggregate: aggregate)

      dbclient.zunionstore(destination, keys, **opts)
    end

    # Stores the intersection of sorted sets into a destination key.
    #
    # @param destination [String] Destination key name
    # @param other_sets [Array<SortedSet, String>] Other sorted sets or key names
    # @param weights [Array<Numeric>, nil] Multiplication factors for each set's scores
    # @param aggregate [Symbol, nil] How to aggregate scores (:sum, :min, :max)
    # @return [Integer] Number of elements in the resulting sorted set
    #
    def interstore(destination, *other_sets, weights: nil, aggregate: nil)
      keys = [dbkey] + resolve_set_keys(other_sets)
      opts = build_set_operation_opts(weights: weights, aggregate: aggregate)

      dbclient.zinterstore(destination, keys, **opts)
    end

    # Returns the difference between this sorted set and other sorted sets.
    #
    # @param other_sets [Array<SortedSet, String>] Other sorted sets or key names
    # @param withscores [Boolean] Whether to include scores in result
    # @return [Array] Members in this set but not in other sets
    #
    # @example Difference of two sorted sets
    #   zset.diff(other_zset)  #=> ["unique_member"]
    #
    def diff(*other_sets, withscores: false)
      keys = [dbkey] + resolve_set_keys(other_sets)

      result = if withscores
        dbclient.zdiff(*keys, withscores: true)
      else
        dbclient.zdiff(*keys)
      end

      process_set_operation_result(result, withscores: withscores)
    end

    # Stores the difference of sorted sets into a destination key.
    #
    # @param destination [String] Destination key name
    # @param other_sets [Array<SortedSet, String>] Other sorted sets or key names
    # @return [Integer] Number of elements in the resulting sorted set
    #
    def diffstore(destination, *other_sets)
      keys = [dbkey] + resolve_set_keys(other_sets)
      dbclient.zdiffstore(destination, keys)
    end


    private

    # Resolves sorted set arguments to their Redis key names.
    #
    # @param sets [Array<SortedSet, String>] Sorted sets or key names
    # @return [Array<String>] Array of Redis key names
    #
    def resolve_set_keys(sets)
      sets.map do |s|
        case s
        when Familia::SortedSet
          s.dbkey
        when String
          s
        else
          raise ArgumentError, "Expected SortedSet or String key, got #{s.class}"
        end
      end
    end

    # Builds options hash for set operations (union, inter, diff).
    #
    # @param weights [Array<Numeric>, nil] Score multiplication factors
    # @param aggregate [Symbol, nil] Score aggregation method
    # @param withscores [Boolean] Whether to include scores
    # @return [Hash] Options hash for Redis command
    #
    def build_set_operation_opts(weights: nil, aggregate: nil, withscores: false)
      opts = {}
      opts[:weights] = weights if weights
      opts[:aggregate] = aggregate.to_s.upcase if aggregate
      opts[:with_scores] = true if withscores
      opts
    end

    # Processes the result of set operations, deserializing values.
    #
    # @param result [Array] Raw result from Redis
    # @param withscores [Boolean] Whether result includes scores
    # @return [Array] Deserialized result
    #
    def process_set_operation_result(result, withscores: false)
      return [] if result.nil? || result.empty?

      if withscores
        result.map { |member, score| [deserialize_value(member), score.to_f] }
      else
        deserialize_values(*result)
      end
    end

    # Validates that mutually exclusive ZADD options are not specified together.
    #
    # @param nx [Boolean] NX option flag
    # @param xx [Boolean] XX option flag
    # @param gt [Boolean] GT option flag
    # @param lt [Boolean] LT option flag
    #
    # @raise [ArgumentError] If mutually exclusive options are specified
    #
    # @note Valid combinations: XX+GT, XX+LT
    # @note Invalid combinations: NX+XX, GT+LT, NX+GT, NX+LT
    #
    def validate_zadd_options!(nx:, xx:, gt:, lt:)
      # NX and XX are mutually exclusive
      if nx && xx
        raise ArgumentError, "ZADD options NX and XX are mutually exclusive"
      end

      # GT and LT are mutually exclusive
      if gt && lt
        raise ArgumentError, "ZADD options GT and LT are mutually exclusive"
      end

      # NX is mutually exclusive with GT
      if nx && gt
        raise ArgumentError, "ZADD options NX and GT are mutually exclusive"
      end

      # NX is mutually exclusive with LT
      if nx && lt
        raise ArgumentError, "ZADD options NX and LT are mutually exclusive"
      end

      # Note: XX + GT and XX + LT are valid combinations
    end

    Familia::DataType.register self, :sorted_set
    Familia::DataType.register self, :zset
  end
end
