# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Methods that call load and dump (InstanceMethods)
    #
    module Serialization
      #include Familia::RedisType::Serialization

      attr_writer :redis

      def redis
        @redis || self.class.redis
      end

      def transaction
        original_redis = self.redis

        begin
          redis.multi do |conn|
            self.instance_variable_set(:@redis, conn)
            yield(conn)
          end
        ensure
          self.redis = original_redis
        end
      end

      def save
        Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first if Familia.debug?

        ret = commit_fields
        ['OK', true, 1].include?(ret)
      end

      def commit_fields
        transaction do |conn|
          hmset(to_h)
          update_expiration
        end
      end

      def destroy!
        delete!
      end

      def to_h
        # Use self.class.fields to efficiently generate a hash
        # of all the fields for this object
        self.class.fields.inject({}) do |hsh, field|
          val = send(field)
          prepared = val.to_s
          Familia.ld " [to_h] field: #{field} val: #{val.class} prepared: #{prepared.class}"
          hsh[field] = prepared
          hsh
        end
      end

      def to_a
        self.class.fields.map do |field|
          val = send(field)
          Familia.ld " [to_a] field: #{field} val: #{val}"
          to_redis(val)
        end
      end

      def to_redis(val)

        prepared = case val.class
              when ::Symbol, ::String, ::Numeric
                val.to_s
              when ::NilClass
                ''
              else
                if val.respond_to? dump_method
                  val.send dump_method

                else
                  raise Familia::Problem, "No such method: #{val.class}.#{dump_method}"
                end
              end

        Familia.ld "[#{self.class}\#to_redis] nil returned for #{self.class}\##{name}" if prepared.nil?
        prepared
      end

      def update_expiration(ttl = nil)
        ttl ||= opts[:ttl]
        return if ttl.to_i.zero? # nil will be zero

        Familia.ld "#{rediskey} to #{ttl}"
        expire ttl.to_i
      end
    end

    include Serialization # these become Horreum instance methods
  end
end

__END__



# From RedisHash
def save
  hsh = { :key => identifier }
  ret = commit_fields hsh
  ret == "OK"
end

def update_fields hsh={}
  check_identifier!
  hsh[:updated] = OT.now.to_i
  hsh[:created] = OT.now.to_i unless has_key?(:created)
  ret = update hsh  # update is defined in HashKey
  ## NOTE: caching here like this only works if hsh has all keys
  #self.cache.replace hsh
  ret
end
