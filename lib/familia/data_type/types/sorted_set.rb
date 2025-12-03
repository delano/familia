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


    private

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
