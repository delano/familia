# lib/familia/datatype/commands.rb

class Familia::DataType

  # Must be included in all DataType classes to provide Redis
  # commands. The class must have a dbkey method.
  module Commands

    def move(logical_database)
      redis.move dbkey, logical_database
    end

    def rename(newkey)
      redis.rename dbkey, newkey
    end

    def renamenx(newkey)
      redis.renamenx dbkey, newkey
    end

    def type
      redis.type dbkey
    end

    # Deletes the entire dbkey
    # @return [Boolean] true if the key was deleted, false otherwise
    def delete!
      Familia.trace :DELETE!, redis, redisuri, caller(1..1) if Familia.debug?
      ret = redis.del dbkey
      ret.positive?
    end
    alias clear delete!

    def exists?
      redis.exists(dbkey) && !size.zero?
    end

    def current_expiration
      redis.ttl dbkey
    end

    def expire(sec)
      redis.expire dbkey, sec.to_i
    end

    def expireat(unixtime)
      redis.expireat dbkey, unixtime
    end

    def persist
      redis.persist dbkey
    end

    def echo(meth, trace)
      redis.echo "[#{self.class}\##{meth}] #{trace} (#{@opts[:class]}\#)"
    end

  end
end
