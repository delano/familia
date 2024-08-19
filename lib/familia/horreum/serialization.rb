# rubocop:disable all
#
module Familia


  # Familia::Horreum
  #
  class Horreum
    # Serialization: Where Objects Go to Become Strings (and Vice Versa)!
    #
    # This module is chock-full of methods that'll make your head spin (in a
    # good way)! We've got loaders, dumpers, and refreshers galore. It's like
    # a laundromat for your data, but instead of quarters, it runs on Redis commands.
    #
    # A Note on Our Refreshing Refreshers:
    # In the wild world of Ruby, '!' usually means "Watch out! I'm dangerous!"
    # But here in Familia-land, we march to the beat of a different drummer.
    # Our refresh! method is the real deal, doing all the heavy lifting.
    # The non-bang refresh? Oh, it's just as rowdy, but it plays nice with
    # method chaining. It's like the polite twin who still knows how to party.
    #
    # Remember: In Familia, refreshing isn't just a chore, it's a chance to
    # dance with data! Whether you bang(!) or not, you're still invited to
    # the Redis disco.
    #
    # (P.S. If you're reading these docs, lol sorry. I asked Claude 3.5 to
    # write in the style of _why the lucky stiff today and got this uncanny
    # valley response. I hope you enjoy reading it as much as I did writing
    # the prompt for it. - @delano).
    #
    # (Ahem! What I meant to say was that if you're reading this, congratulations!
    # You've stumbled upon the secret garden of documentation. Feel free to smell
    # the Ruby roses, but watch out for the Redis thorns!)
    #
    module Serialization

      attr_writer :redis

      # Summon the mystical Redis connection from the depths of instance or class.
      #
      # This method is like a magical divining rod, always pointing to the nearest
      # source of Redis goodness. It first checks if we have a personal Redis
      # connection (@redis), and if not, it borrows the class's connection.
      #
      # @return [Redis] A shimmering Redis connection, ready for your bidding.
      #
      # @example Finding your Redis way
      #   puts object.redis
      #   # => #<Redis client v4.5.1 for redis://localhost:6379/0>
      #
      def redis
        @redis || self.class.redis
      end

      # Perform a sacred Redis transaction ritual.
      #
      # This method creates a protective circle around your Redis operations,
      # ensuring they all succeed or fail together. It's like a group hug for your
      # data operations, but with more ACID properties.
      #
      # @yield [conn] A block where you can perform your Redis incantations.
      # @yieldparam conn [Redis] A Redis connection in multi mode.
      #
      # @example Performing a Redis rain dance
      #   transaction do |conn|
      #     conn.set("weather", "rainy")
      #     conn.set("mood", "melancholic")
      #   end
      #
      # @note This method temporarily replaces your Redis connection with a multi
      #   connection. Don't worry, it puts everything back where it found it when it's done.
      #
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

      # Save our precious data to Redis, with a sprinkle of timestamp magic!
      #
      # This method is like a conscientious historian, not only recording your
      # object's current state but also meticulously timestamping when it was
      # created and last updated. It's the record keeper of your data's life story!
      #
      # @return [Boolean] true if the save was successful, false if Redis was grumpy.
      #
      # @example Preserving your pet rock for posterity
      #   rocky = PetRock.new(name: "Dwayne")
      #   rocky.save
      #   # => true (Dwayne is now immortalized in Redis)
      #
      # @note This method will leave breadcrumbs (traces) if you're in debug mode.
      #   It's like Hansel and Gretel, but for data operations!
      #
      def save
        Familia.trace :SAVE, redis, redisuri, caller(1..1) if Familia.debug?

        # Update our object's life story
        self.key ||= self.identifier
        self.updated = Familia.now.to_i
        self.created ||= Familia.now.to_i

        # Commit our tale to the Redis chronicles
        ret = commit_fields # e.g. ["OK"]

        Familia.ld "[save] #{self.class} #{rediskey} #{ret}"

        # Did Redis accept our offering?
        ret.uniq.all? { |value| value == "OK" }
      end

      # Apply a smattering of fields to this object like fairy dust.
      #
      # @param fields [Hash] A magical bag of named attributes to sprinkle onto this instance.
      #   Each key-value pair is like a tiny spell, ready to enchant our object's properties.
      #
      # @return [self] Returns the newly bejeweled instance, now sparkling with fresh attributes.
      #
      # @example Giving your object a makeover
      #   dragon.apply_fields(name: "Puff", breathes: "fire", loves: "little boys named Jackie")
      #   # => #<Dragon:0x007f8a1c8b0a28 @name="Puff", @breathes="fire", @loves="little boys named Jackie">
      #
      def apply_fields(**fields)
        fields.each do |field, value|
          # Whisper the new value into the object's ear (if it's listening)
          send("#{field}=", value) if respond_to?("#{field}=")
        end
        self
      end

      # Commit our precious fields to Redis.
      #
      # This method performs a sacred ritual, sending our cherished attributes
      # on a journey through the ethernet to find their resting place in Redis.
      #
      # @return [Array<String>] A mystical array of strings, cryptic messages from the Redis gods.
      #
      # @note Be warned, young programmer! This method dabbles in the arcane art of transactions.
      #   Side effects may include data persistence and a slight tingling sensation.
      #
      # @example Offering your changes to the Redis deities
      #   unicorn.name = "Charlie"
      #   unicorn.horn_length = "magnificent"
      #   unicorn.commit_fields
      #   # => ["OK", "OK"] (The Redis gods are pleased with your offering)
      #
      def commit_fields
        Familia.ld "[commit_fields] #{self.class} #{rediskey} #{to_h}"
        transaction do |conn|
          hmset
          update_expiration
        end
      end

      # Dramatically vanquish this object from the face of Redis! (ed: delete it)
      #
      # This method is the doomsday device of our little data world. It will
      # mercilessly eradicate all traces of our object from Redis, leaving naught
      # but digital dust in its wake. Use with caution, lest you accidentally
      # destroy the wrong data-verse!
      #
      # @return [void] Returns nothing, for nothing remains after destruction.
      #
      # @example Bidding a fond farewell to your pet rock
      #   rocky = PetRock.new(name: "Dwayne")
      #   rocky.destroy!
      #   # => *poof* Rocky is no more. A moment of silence, please.
      #
      # @note If debugging is enabled, this method will leave a trace of its
      #   destructive path, like breadcrumbs for future data archaeologists.
      #
      # @see #delete! The actual hitman carrying out the deed.
      #
      def destroy!
        Familia.trace :DESTROY, redis, redisuri, caller(1..1) if Familia.debug?
        delete!
      end


      # Refreshes the object's state by querying Redis and overwriting the
      # current field values. This method performs a destructive update on the
      # object, regardless of unsaved changes.
      #
      # @note This is a destructive operation that will overwrite any unsaved
      #   changes.
      # @return The list of field names that were updated.
      def refresh!
        Familia.trace :REFRESH, redis, redisuri, caller(1..1) if Familia.debug?
        fields = hgetall
        Familia.ld "[refresh!] #{self.class} #{rediskey} #{fields.keys}"
        optimistic_refresh(**fields)
      end

      # Refreshes the object's state and returns self to allow method chaining.
      # This method calls refresh! internally, performing the actual Redis
      # query and state update.
      #
      # @note While this method allows chaining, it still performs a
      #   destructive update like refresh!.
      # @return [self] Returns the object itself after refreshing, allowing
      #   method chaining.
      def refresh
        refresh!
        self
      end

      # Transform this object into a magical hash of wonders!
      #
      # This method performs an alchemical transmutation, turning our noble object
      # into a more plebeian hash. But fear not, for in this form, it can slip through
      # the cracks of the universe (or at least, into Redis) with ease.
      #
      # @return [Hash] A glittering hash, each key a field name, each value a Redis-ready treasure.
      #
      # @example Turning your dragon into a hash
      #   dragon.to_h
      #   # => {"name"=>"Puff", "breathes"=>"fire", "age"=>1000}
      #
      # @note Watch in awe as each field is lovingly prepared for its Redis adventure!
      #
      def to_h
        self.class.fields.inject({}) do |hsh, field|
          val = send(field)
          prepared = to_redis(val)
          Familia.ld " [to_h] field: #{field} val: #{val.class} prepared: #{prepared.class}"
          hsh[field] = prepared
          hsh
        end
      end

      # Line up all our attributes in a neat little array parade!
      #
      # This method marshals all our object's attributes into an orderly procession,
      # ready to march into Redis in perfect formation. It's like a little data army,
      # but friendlier and less prone to conquering neighboring databases.
      #
      # @return [Array] A splendid array of Redis-ready values, in the order of our fields.
      #
      # @example Arranging your unicorn's attributes in a line
      #   unicorn.to_a
      #   # => ["Charlie", "magnificent", 5]
      #
      # @note Each value is carefully disguised in its Redis costume before joining the parade.
      #
      def to_a
        self.class.fields.map do |field|
          val = send(field)
          prepared = to_redis(val)
          Familia.ld " [to_a] field: #{field} val: #{val.class} prepared: #{prepared.class}"
          prepared
        end
      end

      # The to_redis method in Familia::Redistype and Familia::Horreum serve
      # similar purposes but have some key differences in their implementation:
      #
      # Similarities:
      # - Both methods aim to serialize various data types for Redis storage
      # - Both handle basic data types like String, Symbol, and Numeric
      # - Both have provisions for custom serialization methods
      #
      # Differences:
      # - Familia::Redistype uses the opts[:class] for type hints
      # - Familia::Horreum had more explicit type checking and conversion
      # - Familia::Redistype includes more extensive debug tracing
      #
      # The centralized Familia.distinguisher method accommodates both approaches
      # by:
      # 1. Handling a wide range of data types, including those from both
      #    implementations
      # 2. Providing a 'strict_values' option for flexible type handling
      # 3. Supporting custom serialization through a dump_method
      # 4. Including debug tracing similar to Familia::Redistype
      #
      # By using Familia.distinguisher, we achieve more consistent behavior
      # across different parts of the library while maintaining the flexibility
      # to handle various data types and custom serialization needs. This
      # centralization also makes it easier to extend or modify serialization
      # behavior in the future.
      #
      def to_redis(val)
        prepared = Familia.distinguisher(val, false)

        if prepared.nil? && val.respond_to?(dump_method)
          prepared = val.send(dump_method)
        end

        if prepared.nil?
          Familia.ld "[#{self.class}#to_redis] nil returned for #{self.class}##{name}"
        end

        prepared
      end

    end
    # End of Serialization module

    include Serialization # these become Horreum instance methods
  end
end
