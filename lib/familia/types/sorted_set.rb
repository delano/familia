module Familia
  class SortedSet < RedisType
    def size
      redis.zcard rediskey
    end
    alias length size

    def empty?
      size.zero?
    end

    # NOTE: The argument order is the reverse of #add
    # e.g. obj.metrics[VALUE] = SCORE
    def []=(val, score)
      add score, val
    end

    # NOTE: The argument order is the reverse of #[]=
    def add(score, val)
      ret = redis.zadd rediskey, score, to_redis(val)
      update_expiration
      ret
    end

    def score(val)
      ret = redis.zscore rediskey, to_redis(val)
      ret&.to_f
    end
    alias [] score

    def member?(val)
      !rank(val).nil?
    end
    alias include? member?

    # rank of member +v+ when ordered lowest to highest (starts at 0)
    def rank(v)
      ret = redis.zrank rediskey, to_redis(v)
      ret&.to_i
    end

    # rank of member +v+ when ordered highest to lowest (starts at 0)
    def revrank(v)
      ret = redis.zrevrank rediskey, to_redis(v)
      ret&.to_i
    end

    def members(count = -1, opts = {})
      count -= 1 if count.positive?
      el = membersraw count, opts
      multi_from_redis(*el)
    end
    alias to_a members
    alias all members

    def membersraw(count = -1, opts = {})
      count -= 1 if count.positive?
      rangeraw 0, count, opts
    end

    def revmembers(count = -1, opts = {})
      count -= 1 if count.positive?
      el = revmembersraw count, opts
      multi_from_redis(*el)
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
      el = rangeraw(sidx, eidx, opts)
      multi_from_redis(*el)
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
      el = revrangeraw(sidx, eidx, opts)
      multi_from_redis(*el)
    end

    def revrangeraw(sidx, eidx, opts = {})
      redis.zrevrange(rediskey, sidx, eidx, **opts)
    end

    # e.g. obj.metrics.rangebyscore (now-12.hours), now, :limit => [0, 10]
    def rangebyscore(sscore, escore, opts = {})
      echo :rangebyscore, caller(1..1).first if Familia.debug
      el = rangebyscoreraw(sscore, escore, opts)
      multi_from_redis(*el)
    end

    def rangebyscoreraw(sscore, escore, opts = {})
      echo :rangebyscoreraw, caller(1..1).first if Familia.debug
      redis.zrangebyscore(rediskey, sscore, escore, **opts)
    end

    # e.g. obj.metrics.revrangebyscore (now-12.hours), now, :limit => [0, 10]
    def revrangebyscore(sscore, escore, opts = {})
      echo :revrangebyscore, caller(1..1).first if Familia.debug
      el = revrangebyscoreraw(sscore, escore, opts)
      multi_from_redis(*el)
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

    def delete(val)
      redis.zrem rediskey, to_redis(val)
    end
    alias remove delete
    alias rem delete
    alias del delete

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
