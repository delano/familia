# frozen_string_literal: true

module Familia
  class Set < RedisType
    def size
      redis.scard rediskey
    end
    alias length size

    def empty?
      size.zero?
    end

    def add *values
      values.flatten.compact.each { |v| redis.sadd? rediskey, to_redis(v) }
      update_expiration
      self
    end

    def <<(v)
      add v
    end

    def members
      echo :members, caller(1..1).first if Familia.debug
      el = membersraw
      multi_from_redis(*el)
    end
    alias all members
    alias to_a members

    def membersraw
      redis.smembers(rediskey)
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

    def member?(val)
      redis.sismember rediskey, to_redis(val)
    end
    alias include? member?

    def delete(val)
      redis.srem rediskey, to_redis(val)
    end
    alias remove delete
    alias rem delete
    alias del delete

    def intersection *setkeys
      # TODO
    end

    def pop
      redis.spop rediskey
    end

    def move(dstkey, val)
      redis.smove rediskey, dstkey, val
    end

    def random
      from_redis randomraw
    end

    def randomraw
      redis.srandmember(rediskey)
    end

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

    Familia::RedisType.register self, :set
  end
end
