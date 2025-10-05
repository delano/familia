# lib/familia/data_type/commands.rb

module Familia
  class DataType
    # Must be included in all DataType classes to provide Valkey/Redis
    # commands. The class must have a dbkey method.
    module Commands
      def move(logical_database)
        dbclient.move dbkey, logical_database
      end

      def rename(newkey)
        dbclient.rename dbkey, newkey
      end

      def renamenx(newkey)
        dbclient.renamenx dbkey, newkey
      end

      def type
        dbclient.type dbkey
      end

      # Deletes the entire dbkey
      # @return [Boolean] true if the key was deleted, false otherwise
      def delete!
        Familia.trace :DELETE!, nil, uri if Familia.debug?
        ret = dbclient.del dbkey
        ret.positive?
      end
      alias clear delete!

      def exists?
        dbclient.exists(dbkey) && !size.zero?
      end

      def current_expiration
        dbclient.ttl dbkey
      end

      def expire(sec)
        dbclient.expire dbkey, sec.to_i
      end

      def expireat(unixtime)
        dbclient.expireat dbkey, unixtime
      end

      def persist
        dbclient.persist dbkey
      end

      def echo(*args)
        dbclient.echo "[#{self.class}] #{args.join(' ')} (#{opts&.fetch(:class, '<no opts>')})"
      end
    end
  end
end
