# lib/familia/data_type/database_commands.rb
#
# frozen_string_literal: true

module Familia
  class DataType
    # Must be included in all DataType classes to provide Valkey/Redis
    # commands. The class must have a dbkey method.
    module DatabaseCommands
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
      #
      # We return the dbclient.del command's return value instead of a friendly
      # boolean b/c that logic doesn't work inside of a transaction. The return
      # value in that case is a Redis::Future which based on the name indicates
      # that the commend hasn't even run yet.
      def delete!
        Familia.trace :DELETE!, nil, self.class.uri if Familia.debug?
         dbclient.del dbkey
      end
      alias clear delete!

      # EXISTS returns an Integer match count (0 for a missing key). The prior
      # `dbclient.exists(dbkey) && !size.zero?` never short-circuited, since 0
      # is truthy in Ruby -- so existence was actually decided by the size
      # check, which some scalar types (see StringKey#char_count) computed from
      # a never-nil display string and so got wrong for a missing key.
      # Familia.positive? coerces the count to a real boolean, and passes a
      # Redis::Future through untouched inside a pipeline/transaction.
      def exists?
        Familia.positive?(dbclient.exists(dbkey))
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
