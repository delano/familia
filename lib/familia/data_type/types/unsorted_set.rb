# lib/familia/data_type/types/unsorted_set.rb

module Familia
  class UnsortedSet < DataType
    # Returns the number of elements in the unsorted set
    # @return [Integer] number of elements
    def element_count
      dbclient.scard dbkey
    end
    alias size element_count

    def empty?
      element_count.zero?
    end

    def add *values
      values.flatten.compact.each { |v| dbclient.sadd? dbkey, serialize_value(v) }
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
      dbclient.smembers(dbkey)
    end

    def each(&)
      members.each(&)
    end

    def each_with_index(&)
      members.each_with_index(&)
    end

    def collect(&)
      members.collect(&)
    end

    def select(&)
      members.select(&)
    end

    def eachraw(&)
      membersraw.each(&)
    end

    def eachraw_with_index(&)
      membersraw.each_with_index(&)
    end

    def collectraw(&)
      membersraw.collect(&)
    end

    def selectraw(&)
      membersraw.select(&)
    end

    def member?(val)
      dbclient.sismember dbkey, serialize_value(val)
    end
    alias include? member?

    # Removes a member from the set
    # @param value The value to remove from the set
    # @return [Integer] The number of members that were removed (0 or 1)
    def remove_element(value)
      dbclient.srem dbkey, serialize_value(value)
    end
    alias remove remove_element # deprecated

    def intersection *setkeys
      # TODO
    end

    def pop
      dbclient.spop dbkey
    end

    def move(dstkey, val)
      dbclient.smove dbkey, dstkey, val
    end

    def random
      deserialize_value randomraw
    end

    def randomraw
      dbclient.srandmember(dbkey)
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
    Familia::DataType.register self, :unsorted_set
  end
end
