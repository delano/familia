# frozen_string_literal: true

module Familia
  class List < RedisType
    def size
      redis.llen rediskey
    end
    alias length size

    def empty?
      size.zero?
    end

    def push *values
      echo :push, caller(1..1).first if Familia.debug
      values.flatten.compact.each { |v| redis.rpush rediskey, to_redis(v) }
      redis.ltrim rediskey, -@opts[:maxlength], -1 if @opts[:maxlength]
      update_expiration
      self
    end

    def <<(val)
      push val
    end
    alias add <<

    def unshift *values
      values.flatten.compact.each { |v| redis.lpush rediskey, to_redis(v) }
      # TODO: test maxlength
      redis.ltrim rediskey, 0, @opts[:maxlength] - 1 if @opts[:maxlength]
      update_expiration
      self
    end

    def pop
      from_redis redis.rpop(rediskey)
    end

    def shift
      from_redis redis.lpop(rediskey)
    end

    def [](idx, count = nil)
      if idx.is_a? Range
        range idx.first, idx.last
      elsif count
        case count <=> 0
        when 1  then range(idx, idx + count - 1)
        when 0  then []
        when -1 then nil
        end
      else
        at idx
      end
    end
    alias slice []

    def delete(v, count = 0)
      redis.lrem rediskey, count, to_redis(v)
    end
    alias remove delete
    alias rem delete
    alias del delete

    def range(sidx = 0, eidx = -1)
      el = rangeraw sidx, eidx
      multi_from_redis(*el)
    end

    def rangeraw(sidx = 0, eidx = -1)
      redis.lrange(rediskey, sidx, eidx)
    end

    def members(count = -1)
      echo :members, caller(1..1).first if Familia.debug
      count -= 1 if count.positive?
      range 0, count
    end
    alias all members
    alias to_a members

    def membersraw(count = -1)
      count -= 1 if count.positive?
      rangeraw 0, count
    end

    def each(&blk)
      range.each(&blk)
    end

    def each_with_index(&blk)
      range.each_with_index(&blk)
    end

    def eachraw(&blk)
      rangeraw.each(&blk)
    end

    def eachraw_with_index(&blk)
      rangeraw.each_with_index(&blk)
    end

    def collect(&blk)
      range.collect(&blk)
    end

    def select(&blk)
      range.select(&blk)
    end

    def collectraw(&blk)
      rangeraw.collect(&blk)
    end

    def selectraw(&blk)
      rangeraw.select(&blk)
    end

    def at(idx)
      from_redis redis.lindex(rediskey, idx)
    end

    def first
      at 0
    end

    def last
      at(-1)
    end

    # TODO: def replace
    ## Make the value stored at KEY identical to the given list
    # define_method :"#{name}_sync" do |*latest|
    #  latest = latest.flatten.compact
    #  # Do nothing if we're given an empty Array.
    #  # Otherwise this would clear all current values
    #  if latest.empty?
    #    false
    #  else
    #    # Convert to a list of index values if we got the actual objects
    #    latest = latest.collect { |obj| obj.index } if klass === latest.first
    #    current = send("#{name_plural}raw")
    #    added = latest-current
    #    removed = current-latest
    #    #Familia.info "#{self.index}: adding: #{added}"
    #    added.each { |v| self.send("add_#{name_singular}", v) }
    #    #Familia.info "#{self.index}: removing: #{removed}"
    #    removed.each { |v| self.send("remove_#{name_singular}", v) }
    #    true
    #  end
    # end

    Familia::RedisType.register self, :list
  end
end
