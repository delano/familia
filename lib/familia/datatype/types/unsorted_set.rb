# lib/familia/datatype/types/unsorted_set.rb

module Familia
  class Set < DataType

    # Returns the number of elements in the unsorted set
    # @return [Integer] number of elements
    def element_count
      redis.scard dbkey
    end
    alias size element_count

    def empty?
      element_count.zero?
    end

    def add *values
      values.flatten.compact.each { |v| redis.sadd? dbkey, serialize_value(v) }
      update_expiration
      self
    end

    def <<(v)
      add v
    end

    def members
      echo :members, caller(1..1).first if Familia.debug
      elements = membersraw
      deserialize_values(*elements)
    end
    alias all members
    alias to_a members

    def membersraw
      redis.smembers(dbkey)
    end

    def each(&blk)
      members.each(&blk)
    end

    def each_with_index(&blk)
      members.each_with_index(&blk)
    end

    def collect(&blk)
      members.collect(&blk)
    end

    def select(&blk)
      members.select(&blk)
    end

    def eachraw(&blk)
      membersraw.each(&blk)
    end

    def eachraw_with_index(&blk)
      membersraw.each_with_index(&blk)
    end

    def collectraw(&blk)
      membersraw.collect(&blk)
    end

    def selectraw(&blk)
      membersraw.select(&blk)
    end

    def member?(val)
      redis.sismember dbkey, serialize_value(val)
    end
    alias include? member?

    # Removes a member from the set
    # @param value The value to remove from the set
    # @return [Integer] The number of members that were removed (0 or 1)
    def remove_element(value)
      redis.srem dbkey, serialize_value(value)
    end
    alias remove remove_element # deprecated

    def intersection *setkeys
      # TODO
    end

    def pop
      redis.spop dbkey
    end

    def move(dstkey, val)
      redis.smove dbkey, dstkey, val
    end

    def random
      deserialize_value randomraw
    end

    def randomraw
      redis.srandmember(dbkey)
    end

    ## Make the value stored at KEY identical to the given list
    # define_method :"#{name}_sync" do |*latest|
    #  latest = latest.flatten.compact
    #  # Do nothing if we're given an empty Array.
    #  # Otherwise this would clear all current values
    #  if latest.empty?
    #    false
    #  else
    #    # Convert to a list of index values if we got the actual objects
    #    latest = latest.collect { |obj| obj.index } if klass === latest.first
    #    current = send("#{name_plural}raw")
    #    added = latest-current
    #    removed = current-latest
    #    #Familia.info "#{self.index}: adding: #{added}"
    #    added.each { |v| self.send("add_#{name_singular}", v) }
    #    #Familia.info "#{self.index}: removing: #{removed}"
    #    removed.each { |v| self.send("remove_#{name_singular}", v) }
    #    true
    #  end
    # end

    Familia::DataType.register self, :set
  end
end
