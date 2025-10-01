# lib/familia/data_type/types/unsorted_set.rb

module Familia
  # Familia::UnsortedSet
  #
  class UnsortedSet < DataType
    # Returns the number of elements in the unsorted set
    # @return [Integer] number of elements
    def element_count
      dbclient.scard dbkey
    end
    alias size element_count
    alias length element_count
    alias count element_count

    def empty?
      element_count.zero?
    end

    def add *values
      values.flatten.compact.each { |v| dbclient.sadd? dbkey, serialize_value(v) }
      update_expiration
      self
    end
    alias add_element add

    def <<(v)
      add v
    end

    def members
      echo :members, Familia.pretty_stack(limit: 1) if Familia.debug
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

    # Get one or more random members from the set
    # @param count [Integer] Number of random members to return (default: 1)
    # @return [Array] Array of deserialized random members
    def sample(count = 1)
      deserialize_values(*sampleraw(count))
    end
    alias random sample

    # Get one or more random members from the set without deserialization
    # @param count [Integer] Number of random members to return (default: 1)
    # @return [Array] Array of raw random members
    def sampleraw(count = 1)
      dbclient.srandmember(dbkey, count) || []
    end
    alias random sampleraw

    Familia::DataType.register self, :set
    Familia::DataType.register self, :unsorted_set
  end
end
