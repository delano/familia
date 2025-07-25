# lib/familia/horreum/serialization.rb
#
module Familia


  # Familia::Horreum
  #
  class Horreum
    # The Sacred Scrolls of Database Responses
    #
    # Behold! The mystical runes that Database whispers back to us:
    #
    # "OK" - The sweet sound of success, like a tiny "ding!" from the depths of data.
    # true  - The boolean Buddha nods in agreement.
    # 1     - A lonely digit, standing tall and proud. "I did something!" it proclaims.
    # 0     - The silent hero. It tried its best, bless its heart.
    # nil   - The zen master of responses. It's not nothing, it's... enlightenment!
    #
    # These sacred signs are our guide through the Database wilderness. When we cast
    # our spells (er, commands), we seek these friendly faces in the returned
    # smoke signals.
    #
    # Should our Database rituals summon anything else, we pause. We ponder. We
    # possibly panic. For the unexpected in Redis-land is like finding a penguin
    # in your pasta - delightfully confusing, but probably not what you ordered.
    #
    # May your Database returns be ever valid, and your data ever flowing!
    #
    @valid_command_return_values = ["OK", true, 1, 0, nil].freeze

    class << self
      attr_reader :valid_command_return_values
    end

    # Serialization: Where Objects Go to Become Strings (and Vice Versa)!
    #
    # This module is chock-full of methods that'll make your head spin (in a
    # good way)! We've got loaders, dumpers, and refreshers galore. It's like
    # a laundromat for your data, but instead of quarters, it runs on Database commands.
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
    # the Database disco.
    #
    # (P.S. If you're reading these docs, lol sorry. I asked Claude 3.5 to
    # write in the style of _why the lucky stiff today and got this uncanny
    # valley response. I hope you enjoy reading it as much as I did writing
    # the prompt for it. - @delano).
    #
    # (Ahem! What I meant to say was that if you're reading this, congratulations!
    # You've stumbled upon the secret garden of documentation. Feel free to smell
    # the Ruby roses, but watch out for the Database thorns!)
    #
    module Serialization

      # Save our precious data to Redis, with a sprinkle of timestamp magic!
      #
      # This method is like a conscientious historian, not only recording your
      # object's current state but also meticulously timestamping when it was
      # created and last updated. It's the record keeper of your data's life story!
      #
      # @return [Boolean] true if the save was successful, false if Database was grumpy.
      #
      # @example Preserving your pet rock for posterity
      #   rocky = PetRock.new(name: "Dwayne")
      #   rocky.save
      #   # => true (Dwayne is now immortalized in Redis)
      #
      # @note This method will leave breadcrumbs (traces) if you're in debug mode.
      #   It's like Hansel and Gretel, but for data operations!
      #
      def save update_expiration: true
        Familia.trace :SAVE, dbclient, uri, caller(1..1) if Familia.debug?

        # Update our object's life story, keeping the mandatory built-in
        # key field in sync with the field that is the chosen identifier.
        self.key = self.identifier
        self.created ||= Familia.now.to_i if respond_to?(:created)
        self.updated = Familia.now.to_i if respond_to?(:updated)

        # Commit our tale to the Database chronicles
        #
        ret = commit_fields(update_expiration: update_expiration)

        Familia.ld "[save] #{self.class} #{dbkey} #{ret} (update_expiration: #{update_expiration})"

        # Did Database accept our offering?
        !ret.nil?
      end

      # Updates multiple fields atomically in a Database transaction.
      #
      # @param fields [Hash] Field names and values to update. Special key :update_expiration
      #   controls whether to update key expiration (default: true)
      # @return [MultiResult] Transaction result
      #
      # @example Update multiple fields without affecting expiration
      #   metadata.batch_update(viewed: 1, updated: Time.now.to_i, update_expiration: false)
      #
      # @example Update fields with expiration refresh
      #   user.batch_update(name: "John", email: "john@example.com")
      #
      def batch_update(**kwargs)
        update_expiration = kwargs.delete(:update_expiration) { true }
        fields = kwargs

        Familia.trace :BATCH_UPDATE, dbclient, fields.keys, caller(1..1) if Familia.debug?

        command_return_values = transaction do |conn|
          fields.each do |field, value|
            prepared_value = serialize_value(value)
            conn.hset dbkey, field, prepared_value
            # Update instance variable to keep object in sync
            send("#{field}=", value) if respond_to?("#{field}=")
          end
        end

        # Update expiration if requested and supported
        self.update_expiration(default_expiration: nil) if update_expiration && respond_to?(:update_expiration)

        # Return same MultiResult format as other methods
        summary_boolean = command_return_values.all? { |ret| %w[OK 0 1].include?(ret.to_s) }
        MultiResult.new(summary_boolean, command_return_values)
      end

      # Apply a smattering of fields to this object like fairy dust.
      #
      # @param fields [Hash] A magical bag of named attributes to sprinkle onto
      #   this instance. Each key-value pair is like a tiny spell, ready to
      #   enchant our object's properties.
      #
      # @return [self] Returns the newly bejeweled instance, now sparkling with
      #   fresh attributes.
      #
      # @example Giving your object a makeover
      #   dragon.apply_fields(name: "Puff", breathes: "fire", loves: "Toys
      #   named Jackie")
      #   # => #<Dragon:0x007f8a1c8b0a28 @name="Puff", @breathes="fire",
      #   @loves="Toys named Jackie">
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
      # It executes a transaction that includes setting field values and,
      # if applicable, updating the expiration time.
      #
      # @param update_expiration [Boolean] Whether to update the expiration time
      #  of the dbkey. This is true by default, but can be disabled if you
      #  don't want to mess with the cosmic balance of your key's lifespan.
      #
      # @return [MultiResult] A mystical object containing:
      #   - success: A boolean indicating if all Database commands succeeded
      #   - results: An array of strings, cryptic messages from the Database gods
      #
      # The MultiResult object responds to:
      #   - successful?: Returns the boolean success value
      #   - results: Returns the array of command return values
      #
      # @note Be warned, young programmer! This method dabbles in the arcane
      #   art of transactions. Side effects may include data persistence and a
      #   slight tingling sensation. The method does not raise exceptions for
      #   unexpected Database responses, but logs warnings and returns a failure status.
      #
      # @example Offering your changes to the Database deities
      #   unicorn.name = "Charlie"
      #   unicorn.horn_length = "magnificent"
      #   result = unicorn.commit_fields
      #   if result.successful?
      #     puts "The Database gods are pleased with your offering"
      #     p result.results  # => ["OK", "OK"]
      #   else
      #     puts "The Database gods frown upon your offering"
      #     p result.results  # Examine the unexpected values
      #   end
      #
      # @see Familia::Horreum.valid_command_return_values for the list of
      #   acceptable Database command return values.
      #
      # @note This method performs logging at various levels:
      #   - Debug: Logs the object's class, dbkey, and current state before committing
      #   - Warn: Logs any unexpected return values from Database commands
      #   - Debug: Logs the final result, including success status and all return values
      #
      # @note The expiration update is only performed for classes that have
      #   the expiration feature enabled. For others, it's a no-op.
      #
      def commit_fields update_expiration: true
        prepared_value = to_h
        Familia.ld "[commit_fields] Begin #{self.class} #{dbkey} #{prepared_value} (exp: #{update_expiration})"

        result = self.hmset(prepared_value)

        # Only classes that have the expiration ferature enabled will
        # actually set an expiration time on their keys. Otherwise
        # this will be a no-op that simply logs the attempt.
        self.update_expiration(default_expiration: nil) if update_expiration

        result
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
      # This method is part of Familia's high-level object lifecycle management. While `delete!`
      # operates directly on dbkeys, `destroy!` operates at the object level and is used for
      # ORM-style operations. Use `destroy!` when removing complete objects from the system, and
      # `delete!` when working directly with dbkeys.
      #
      # @note If debugging is enabled, this method will leave a trace of its
      #   destructive path, like breadcrumbs for future data archaeologists.
      #
      # @see #delete! The actual hitman carrying out the deed.
      #
      def destroy!
        Familia.trace :DESTROY, dbclient, uri, caller(1..1) if Familia.debug?
        delete!
      end

      # The Great Nilpocalypse: clear_fields!
      #
      # Imagine your object as a grand old mansion, every room stuffed with
      # trinkets, secrets, and the odd rubber duck. This method? It flings open
      # every window and lets a wild wind of nothingness sweep through, leaving
      # each field as empty as a poet’s wallet.
      #
      # All your precious attributes—gone! Swept into the void! It’s a spring
      # cleaning for the soul, a reset button for your existential dread.
      #
      # @return [void] Nothing left but echoes and nils.
      #
      # @example The Vanishing Act
      #   wizard.clear_fields!
      #   # => All fields are now nil, like a spell gone slightly too well.
      #
      def clear_fields!
        self.class.fields.each { |field| send("#{field}=", nil) }
      end

      # The Great Database Refresh-o-matic 3000
      #
      # Imagine your object as a forgetful time traveler. This method is like
      # zapping it with a memory ray from Redis-topia. ZAP! New memories!
      #
      # WARNING: This is not a gentle mind-meld. It's more like a full brain
      # transplant. Any half-baked ideas floating in your object's head? POOF!
      # Gone quicker than cake at a hobbit's birthday party. Unsaved spells
      # will definitely be forgotten.
      #
      # @return [void] What do you get for this daring act of digital amnesia? A shiny
      # list of all the brain bits that got a makeover!
      #
      # Remember: In the game of Redis-Refresh, you win or you... well, you
      # always win, but sometimes you forget why you played in the first place.
      #
      # @raise [Familia::KeyNotFoundError] If the dbkey does not exist.
      #
      # @example
      #   object.refresh!
      def refresh!
        Familia.trace :REFRESH, dbclient, uri, caller(1..1) if Familia.debug?
        raise Familia::KeyNotFoundError, dbkey unless dbclient.exists(dbkey)
        fields = hgetall
        Familia.ld "[refresh!] #{self.class} #{dbkey} fields:#{fields.keys}"
        optimistic_refresh(**fields)
      end

      # Ah, the magical refresh dance! It's like giving your object a
      # sip from the fountain of youth.
      #
      # This method twirls your object around, dips it into the Database pool,
      # and brings it back sparkling clean and up-to-date. It's using the
      # refresh! spell behind the scenes, so expect some Database whispering.
      #
      # @note Caution, young Rubyist! While this method loves to play
      #   chain-tag with other methods, it's still got that refresh! kick.
      #   It'll update your object faster than you can say "matz!"
      #
      # @return [self] Your object, freshly bathed in Database waters, ready
      #   to dance with more methods in a conga line of Ruby joy!
      #
      # @raise [Familia::KeyNotFoundError] If the dbkey does not exist.
      #
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
      # @return [Hash] A glittering hash, each key a field name, each value a
      #   Redis-ready treasure.
      #
      # @example Turning your dragon into a hash
      #   dragon.to_h
      #   # => {"name"=>"Puff", "breathes"=>"fire", "age"=>1000}
      #
      # @note Watch in awe as each field is lovingly prepared for its Database adventure!
      #
      def to_h
        self.class.fields.inject({}) do |hsh, field|
          val = send(field)
          prepared = serialize_value(val)
          Familia.ld " [to_h] field: #{field} val: #{val.class} prepared: #{prepared&.class || '[nil]'}"

          # Only include non-nil values in the hash for Redis
          hsh[field] = prepared unless prepared.nil?
          hsh
        end
      end

      # Line up all our attributes in a neat little array parade!
      #
      # This method marshals all our object's attributes into an orderly procession,
      # ready to march into Database in perfect formation. It's like a little data army,
      # but friendlier and less prone to conquering neighboring databases.
      #
      # @return [Array] A splendid array of Redis-ready values, in the order of our fields.
      #
      # @example Arranging your unicorn's attributes in a line
      #   unicorn.to_a
      #   # => ["Charlie", "magnificent", 5]
      #
      # @note Each value is carefully disguised in its Database costume
      # before joining the parade.
      #
      def to_a
        self.class.fields.map do |field|
          val = send(field)
          prepared = serialize_value(val)
          Familia.ld " [to_a] field: #{field} val: #{val.class} prepared: #{prepared.class}"
          prepared
        end
      end

      # Behold, the grand tale of two serialization sorcerers:
      # Familia::DataType and Familia::Horreum!
      #
      # These twin wizards, though cut from the same magical cloth,
      # have their own unique spells for turning Ruby objects into
      # Redis-friendly potions. Let's peek into their spell books:
      #
      # Shared Incantations:
      # - Both transform various data creatures for Database safekeeping
      # - They tame wild Strings, Symbols, and those slippery Numerics
      # - Secret rituals (aka custom serialization) are welcome
      #
      # Mystical Differences:
      # - DataType reads the future in opts[:class] tea leaves
      # - Horreum prefers to interrogate types more thoroughly
      # - DataType leaves a trail of debug breadcrumbs
      #
      # But wait! Enter the wise Familia.distinguisher,
      # a grand unifier of serialization magic!
      #
      # This clever mediator:
      # 1. Juggles a circus of data types from both realms
      # 2. Offers a 'strict_values' toggle for the type-obsessed
      # 3. Welcomes custom spells via dump_method
      # 4. Sprinkles debug fairy dust à la DataType
      #
      # By channeling the Familia.distinguisher, we've created a
      # harmonious serialization symphony, flexible enough to dance
      # with any data type that shimmies our way. And should we need
      # to teach it new tricks, we know just where to wave our wands!
      #
      # @param value [Object] The mystical object to be transformed
      #
      # @return [String] The transformed, Redis-ready value.
      #
      def serialize_value(val)
        prepared = Familia.distinguisher(val, strict_values: false)

        # If the distinguisher returns nil, try using the dump_method but only
        # use JSON serialization for complex types that need it.
        if prepared.nil? && (val.is_a?(Hash) || val.is_a?(Array))
          prepared = val.respond_to?(dump_method) ? val.send(dump_method) : JSON.dump(val)
        end

        # If both the distinguisher and dump_method return nil, log an error
        if prepared.nil?
          Familia.ld "[#{self.class}#serialize_value] nil returned for #{self.class}"
        end

        prepared
      end

      # Converts a Database string value back to its original Ruby type
      #
      # This method attempts to deserialize JSON strings back to their original
      # Hash or Array types. Simple string values are returned as-is.
      #
      # @param val [String] The string value from Database to deserialize
      # @param symbolize_keys [Boolean] Whether to symbolize hash keys (default: true for compatibility)
      # @return [Object] The deserialized value (Hash, Array, or original string)
      #
      def deserialize_value(val, symbolize: true)
        return val if val.nil? || val == ""

        # Try to parse as JSON first for complex types
        begin
          parsed = JSON.parse(val, symbolize_names: symbolize)
          # Only return parsed value if it's a complex type (Hash/Array)
          # Simple values should remain as strings
          return parsed if parsed.is_a?(Hash) || parsed.is_a?(Array)
        rescue JSON::ParserError
          # Not valid JSON, return as-is
        end

        val
      end

    end

    include Serialization # these become Horreum instance methods
  end
end
