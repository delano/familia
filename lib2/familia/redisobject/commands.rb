# rubocop:disable all

class Familia::RedisObject

  # Must be included in all RedisObject classes to provide Redis
  # commands. The class must have a rediskey method.
  module Commands

    def move(db)
      redis.move rediskey, db
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

    def delete
      redis.del rediskey
    end
    alias clear delete
    alias del delete

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
