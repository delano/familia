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

      # dbclient.exists returns an Integer (the match count), and 0 is truthy in
      # Ruby, so a bare `dbclient.exists(dbkey) && ...` never short-circuits on a
      # missing key -- the result ends up governed entirely by the second
      # operand. That's harmless for container types (Redis deletes them once
      # empty, so size and existence always agree) but StringKey#to_s falls back
      # to Object#to_s for a nil value, making #size non-zero even when the key
      # is gone. Familia.positive? coerces the count to a real boolean (and
      # passes a Redis::Future through untouched inside a pipeline/transaction).
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
