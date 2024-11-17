# frozen_string_literal: true

module Familia
  class SortedSet < RedisType
    def size
      redis.zcard rediskey
    end
    alias length size

    def empty?
      size.zero?
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
    # @example
    #   sorted_set << "new_element"
    #
    # @note This is a non-standard operation for sorted sets as it doesn't allow
    #   specifying a custom score. Use `add` or `[]=` for more control.
    #
    def <<(val)
      add(Time.now.to_i, val)
    end

    # NOTE: The argument order is the reverse of #add. We do this to
    # more naturally align with how the [] and []= methods are used.
    #
    # e.g.
    #     obj.metrics[VALUE] = SCORE
    #     obj.metrics[VALUE]  # => SCORE
    #
    def []=(val, score)
      add score, val
    end

    def add(score, val)
      ret = redis.zadd rediskey, score, to_redis(val)
      update_expiration
      ret
    end

    def score(val)
      ret = redis.zscore rediskey, to_redis(val, strict_values: false)
      ret&.to_f
    end
    alias [] score

    def member?(val)
      Familia.trace :MEMBER, redis, "#{val}<#{val.class}>", caller(1..1) if Familia.debug?
      !rank(val).nil?
    end
    alias include? member?

    # rank of member +v+ when ordered lowest to highest (starts at 0)
    def rank(v)
      ret = redis.zrank rediskey, to_redis(v, strict_values: false)
      ret&.to_i
    end

    # rank of member +v+ when ordered highest to lowest (starts at 0)
    def revrank(v)
      ret = redis.zrevrank rediskey, to_redis(v, strict_values: false)
      ret&.to_i
    end

    def members(count = -1, opts = {})
      count -= 1 if count.positive?
      elements = membersraw count, opts
      multi_from_redis(*elements)
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
      multi_from_redis(*elements)
    end

    def revmembersraw(count = -1, opts = {})
      count -= 1 if count.positive?
      revrangeraw 0, count, opts
    end

    def each(&blk)
      members.each(&blk)
    end

    def each_with_index(&blk)
      members.each_with_index(&blk)
    end

    def collect(&blk)
      members.collect(&blk)
    end

    def select(&blk)
      members.select(&blk)
    end

    def eachraw(&blk)
      membersraw.each(&blk)
    end

    def eachraw_with_index(&blk)
      membersraw.each_with_index(&blk)
    end

    def collectraw(&blk)
      membersraw.collect(&blk)
    end

    def selectraw(&blk)
      membersraw.select(&blk)
    end

    def range(sidx, eidx, opts = {})
      echo :range, caller(1..1).first if Familia.debug
      elements = rangeraw(sidx, eidx, opts)
      multi_from_redis(*elements)
    end

    def rangeraw(sidx, eidx, opts = {})
      # NOTE: :withscores (no underscore) is the correct naming for the
      # redis-4.x gem. We pass :withscores through explicitly b/c
      # redis.zrange et al only accept that one optional argument.
      # Passing `opts`` through leads to an ArgumentError:
      #
      #   sorted_sets.rb:374:in `zrevrange': wrong number of arguments (given 4, expected 3) (ArgumentError)
      #
      redis.zrange(rediskey, sidx, eidx, **opts)
    end

    def revrange(sidx, eidx, opts = {})
      echo :revrange, caller(1..1).first if Familia.debug
      elements = revrangeraw(sidx, eidx, opts)
      multi_from_redis(*elements)
    end

    def revrangeraw(sidx, eidx, opts = {})
      redis.zrevrange(rediskey, sidx, eidx, **opts)
    end

    # e.g. obj.metrics.rangebyscore (now-12.hours), now, :limit => [0, 10]
    def rangebyscore(sscore, escore, opts = {})
      echo :rangebyscore, caller(1..1).first if Familia.debug
      elements = rangebyscoreraw(sscore, escore, opts)
      multi_from_redis(*elements)
    end

    def rangebyscoreraw(sscore, escore, opts = {})
      echo :rangebyscoreraw, caller(1..1).first if Familia.debug
      redis.zrangebyscore(rediskey, sscore, escore, **opts)
    end

    # e.g. obj.metrics.revrangebyscore (now-12.hours), now, :limit => [0, 10]
    def revrangebyscore(sscore, escore, opts = {})
      echo :revrangebyscore, caller(1..1).first if Familia.debug
      elements = revrangebyscoreraw(sscore, escore, opts)
      multi_from_redis(*elements)
    end

    def revrangebyscoreraw(sscore, escore, opts = {})
      echo :revrangebyscoreraw, caller(1..1).first if Familia.debug
      opts[:with_scores] = true if opts[:withscores]
      redis.zrevrangebyscore(rediskey, sscore, escore, opts)
    end

    def remrangebyrank(srank, erank)
      redis.zremrangebyrank rediskey, srank, erank
    end

    def remrangebyscore(sscore, escore)
      redis.zremrangebyscore rediskey, sscore, escore
    end

    def increment(val, by = 1)
      redis.zincrby(rediskey, by, val).to_i
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
    def remove(value)
      Familia.trace :DELETE, redis, "#{value}<#{value.class}>", caller(1..1) if Familia.debug?
      # We use `strict_values: false` here to allow for the deletion of values
      # that are in the sorted set. If it's a horreum object, the value is
      # the identifier and not a serialized version of the object. So either
      # the value exists in the sorted set or it doesn't -- we don't need to
      # raise an error if it's not found.
      redis.zrem rediskey, to_redis(value, strict_values: false)
    end

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

    Familia::RedisType.register self, :sorted_set
    Familia::RedisType.register self, :zset
  end
end
