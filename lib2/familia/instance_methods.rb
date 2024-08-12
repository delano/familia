# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    #
    # TODO: Needs to be gone through like ClassMethods. Then if they're
    # reasonable sizes they can be put into one file again, horreum.rb obvs.
    #
    module InstanceMethods
      # A default initialize method. This will be replaced
      # if a class defines its own initialize method after
      # including Familia. In that case, the replacement
      # must call initialize_redis_objects.
      def initialize *args
        initialize_redis_objects
        init(*args) if respond_to? :init
      end

      # This needs to be called in the initialize method of
      # any class that includes Familia.
      def initialize_redis_objects
        Familia.ld "[Familia] Initializing #{self.class}"
        # Generate instances of each RedisObject. These need to be
        # unique for each instance of this class so they can piggyback
        # on the specifc index of this instance.
        #
        # i.e.
        #     familia_object.rediskey              == v1:bone:INDEXVALUE:object
        #     familia_object.redis_object.rediskey == v1:bone:INDEXVALUE:name
        #
        # See RedisObject.install_redis_object
        self.class.redis_objects.each_pair do |name, redis_object_definition|
          Familia.ld "[#initialize_redis_objects] #{self.class} #{name} => #{redis_object_definition}"
          klass = redis_object_definition.klass
          opts = redis_object_definition.opts
          opts = opts.nil? ? {} : opts.clone
          opts[:parent] = self unless opts.has_key?(:parent)
          redis_object = klass.new name, opts
          redis_object.freeze
          instance_variable_set "@#{name}", redis_object
        end
      end

      def qstamp(_quantum = nil, pattern = nil, now = Familia.now)
        self.class.qstamp ttl, pattern, now
      end

      def from_redis
        self.class.from_redis index
      end

      def redis
        self.class.redis
      end

      def redisinfo
        info = {
          uri: self.class.uri,
          db: self.class.db,
          key: rediskey,
          type: redistype,
          ttl: realttl
        }
      end

      def exists?
        Familia.redis(self.class.uri).exists rediskey
      end

      # +suffix+ is the value to be used at the end of the redis key
      # + ignored+ is literally ignored. It's around to maintain
      # consistency with the class version of this method.
      # (RedisObject#rediskey may call against a class or instance).
      def rediskey(suffix = nil, ignored = nil)
        Familia.info "[#{self.class}] something was ignored" unless ignored.nil?
        raise Familia::NoIndex, self.class if index.to_s.empty?

        if suffix.nil?
          suffix = if self.class.suffix.is_a?(Proc)
                    self.class.suffix.call(self)
                  else
                    self.class.suffix
                  end
        end
        self.class.rediskey index, suffix
      end

      def object_proxy
        @object_proxy ||= Familia::String.new rediskey, ttl: ttl, class: self.class
        @object_proxy
      end

      def save(meth = :set)
        Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first if Familia.debug?
        preprocess if respond_to?(:preprocess)
        update_time if respond_to?(:update_time)
        ret = object_proxy.send(meth, self) # object is a name reserved by Familia
        unless ret.nil?
          now = Time.now.utc.to_i
          self.class.instances.add now, self
          object_proxy.update_expiration # does nothing unless if not specified
        end
        ['OK', true, 1].include?(ret)
      end

      def savenx
        save :setnx
      end

      def update!(hsh = nil)
        updated = false
        hsh ||= {}
        if hsh.empty?
          raise Familia::Problem, "No #{self.class}#{to_hash} method" unless respond_to?(:to_hash)

          ret = from_redis
          hsh = ret.to_hash if ret
        end
        hsh.keys.each do |field|
          v = hsh[field.to_s] || hsh[field.to_s.to_sym]
          next if v.nil?

          send(:"#{field}=", v)
          updated = true
        end
        updated
      end

      def destroy!
        ret = object_proxy.delete
        if Familia.debug? && Familia.debug?
          Familia.trace :DELETED, Familia.redis(self.class.uri), "#{rediskey}: #{ret}", caller.first
        end
        self.class.instances.rem self if ret > 0
        ret
      end

      def index
        Familia.ld "[#index] #{self.class.index} for #{self.class}"
        case self.class.index
        when Proc
          self.class.index.call(self)
        when Array
          parts = self.class.index.collect do |meth|
            raise NoIndex, "No such method: `#{meth}' for #{self.class}" unless respond_to? meth

            ret = send(meth)
            ret = ret.index if ret.is_a?(Familia)
            ret
          end
          parts.join Familia.delim
        when Symbol, String
          if self.class.redis_object?(self.class.index.to_sym)
            raise Familia::NoIndex, 'Cannot use a RedisObject as an index'
          end

          raise NoIndex, "No such method: `#{self.class.index}' for #{self.class}" unless respond_to? self.class.index

          ret = send(self.class.index)
          ret = ret.index if ret.is_a?(Familia)
          ret

        else
          raise Familia::NoIndex, self
        end
      end

      def index=(v)
        case self.class.index
        when Proc
          raise ArgumentError, 'Cannot set a Proc index'
        when Array
          unless v.is_a?(Array) && v.size == self.class.index.size
            raise ArgumentError, "Index mismatch (#{v.size} for #{self.class.index.size})"
          end

          parts = self.class.index.each_with_index do |meth, idx|
            raise NoIndex, "No such method: `#{meth}=' for #{self.class}" unless respond_to? "#{meth}="

            send("#{meth}=", v[idx])
          end
        when Symbol, String
          if self.class.redis_object?(self.class.index.to_sym)
            raise Familia::NoIndex, 'Cannot use a RedisObject as an index'
          end

          unless respond_to? "#{self.class.index}="
            raise NoIndex, "No such method: `#{self.class.index}=' for #{self.class}"
          end

          send("#{self.class.index}=", v)

        else
          raise Familia::NoIndex, self
        end
      end

      def expire(ttl = nil)
        ttl ||= self.class.ttl
        Familia.redis(self.class.uri).expire rediskey, ttl.to_i
      end

      def realttl
        Familia.redis(self.class.uri).ttl rediskey
      end

      def ttl=(v)
        @ttl = v.to_i
      end

      def ttl
        @ttl || self.class.ttl
      end

      def raw(suffix = nil)
        suffix ||= :object
        Familia.redis(self.class.uri).get rediskey(suffix)
      end

      def redisuri(suffix = nil)
        u = URI.parse self.class.uri.to_s
        u.db ||= self.class.db.to_s
        u.key = rediskey(suffix)
        u
      end

      def redistype(suffix = nil)
        Familia.redis(self.class.uri).type rediskey(suffix)
      end

      # Finds the shortest available unique key (lower limit of 6)
      def shortid
        len = 6
        loop do
          self.class.expand(@id.shorten(len))
          break
        rescue Familia::NonUniqueKey
          len += 1
        end
        @id.shorten(len)
      end
    end
  end
end
