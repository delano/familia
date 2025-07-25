# lib/familia/redistype/commands.rb

class Familia::RedisType

  # Must be included in all RedisType classes to provide Redis
  # commands. The class must have a rediskey method.
  module Commands

    def move(logical_database)
      redis.move rediskey, logical_database
    end

    def rename(newkey)
      redis.rename rediskey, newkey
    end

    def renamenx(newkey)
      redis.renamenx rediskey, newkey
    end

    def type
      redis.type rediskey
    end

    # Deletes the entire Redis key
    # @return [Boolean] true if the key was deleted, false otherwise
    def delete!
      Familia.trace :DELETE!, redis, redisuri, caller(1..1) if Familia.debug?
      ret = redis.del rediskey
      ret.positive?
    end
    alias clear delete!

    def exists?
      redis.exists(rediskey) && !size.zero?
    end

    def realttl
      redis.ttl rediskey
    end

    def expire(sec)
      redis.expire rediskey, sec.to_i
    end

    def expireat(unixtime)
      redis.expireat rediskey, unixtime
    end

    def persist
      redis.persist rediskey
    end

    def echo(meth, trace)
      redis.echo "[#{self.class}\##{meth}] #{trace} (#{@opts[:class]}\#)"
    end

  end
end
