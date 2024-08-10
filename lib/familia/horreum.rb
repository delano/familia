# frozen_string_literal: true

module Familia

  #
  # Differences between Familia::Horreum and Familia::HashKey:
  #
  #   * Horreum is a module, HashKey is a class. When included in a class,
  #     Horreum appears in the list of ancestors without getting involved
  #     in the class hierarchy.
  #   * HashKey is a wrapper around Redis hash operations where every
  #     value change is performed directly on redis; Horreum is a cache
  #     that performs atomic operations on a hash in redis (via HashKey).
  #
  # Differences between Familia and Familia::Horreum:
  #
  #   * Familia provides class/module level access to redis types and
  #     operations; Horreum provides instance-level access to a single
  #     hash in redis.
  #   * Horreum includes Familia and uses `hashkey` to define a redis
  #     has that it refers to as simply "object".
  #
  #
  #
  class Horreum
    include Familia

    hashkey :object
    #attr_accessor :prefix, :identifier, :suffix, :cache

    def initialize *args, **kwargs
      Familia.ld "[Horreum] Initializing #{self.class} with #{args.inspect} and #{kwargs.inspect}"
      initialize_redis_objects
      init(*args) if respond_to? :init
      #super
    end

#    def check_identifier!
#      return unless self.identifier.to_s.empty?
#
#      raise Problem, "Identifier cannot be empty for #{self.class}"
#    end
#
#    def destroy!
#      clear
#    end
#
#    def ttl
#      (get_value(:ttl) || super).to_i
#    end
#
#    def save
#      hsh = { key: identifier }
#      ret = update_fields hsh
#      ret == 'OK'
#    end
#
#    def update_fields(hsh = {})
#      check_identifier!
#      hsh[:updated] = OT.now.to_i
#      hsh[:created] = OT.now.to_i unless has_key?(:created)
#      update hsh
#      ## NOTE: caching here like this only works if hsh has all keys
#      # self.cache.replace hsh
#    end
#
#    def refresh_cache
#      cache.replace all unless self.identifier.to_s.empty?
#    end
#
#    def update_time!
#      check_identifier!
#      OT.ld "[#{self.class}] Updating time for #{self.identifier}"
#      put :updated, OT.now.to_i
#    end
#
#    def cache
#      @cache ||= {}
#      @cache
#    end
#
#    def short_identifier
#      identifier[0, 12]
#    end
#
#    # Support for accessing ModelBase hash keys via method names.
#    # e.g.
#    #     s = OT::Session.new
#    #     s.agent                 #=> nil
#    #     s.agent = "Mozilla..."
#    #     s.agent                 #=> "Mozilla..."
#    #
#    #     s.agent?                # raises NoMethodError
#    #
#    #     s.agent!                #=> "Mozilla..."
#    #     s.agent!                #=> nil
#    #
#    # NOTA BENE: This will hit the internal cache before redis.
#    #
#    def method_missing meth, *args
#      last_char = meth.to_s[-1]
#      field = case last_char
#              when '=', '!', '?'
#                meth.to_s[0..-2]
#              else
#                meth.to_s
#              end
#      # OT.ld "[method_missing] #{field} #{self.class}##{meth}"
#      instance_value = instance_variable_get(:"@#{field}")
#      refresh_cache unless !instance_value.nil? || cache.has_key?(field)
#      case last_char
#      when '='
#        self[field] = cache[field] = args.first.to_s
#      when '!'
#        delete(field) and cache.delete(field) # Hash#delete returns the value
#      when '?'
#        raise NoMethodError, "#{self.class}##{meth}"
#      else
#        cache[field] || instance_value
#      end
#    end

    def get_value(field, bypass_cache = false)
      self.cache ||= {}
      bypass_cache ? self[field] : (self.cache[field] || self[field])
    end
    protected :get_value

  end
end

__END__

re: subclassing vs including a module:

Here's a summarized version for inline documentation:
1. Inheritance vs. Mixin: "Is-a" vs. "has-a" relationship; inheritance vs. behavior sharing.
2. Multiple Inheritance: Classes: single superclass. Modules: multiple inclusions possible.
3. Method Lookup: Class, included modules (reverse order), then superclass chain.
4. Instance Variables: Inherited in subclasses; not automatically shared in modules.
5. `super` Keyword: Calls superclass method in subclass; varies with modules.
6. Ancestor Chain: Superclass directly above subclass; modules between class and superclass.
7. Class Methods: Inherited in subclasses; not by default in modules.
8. Usage Intent: Subclassing for specialization; modules for sharing across classes.
9. Prepending: Modules can be prepended, affecting method lookup order.
