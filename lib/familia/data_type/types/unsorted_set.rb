# lib/familia/data_type/types/unsorted_set.rb
#
# frozen_string_literal: true

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

    # Returns the intersection of this set with one or more other sets.
    # @param other_sets [Array<UnsortedSet, String>] Other sets (as UnsortedSet instances or raw keys)
    # @return [Array] Deserialized members present in all sets
    def intersection(*other_sets)
      keys = extract_keys(other_sets)
      elements = dbclient.sinter(dbkey, *keys)
      deserialize_values(*elements)
    end
    alias inter intersection

    # Returns the union of this set with one or more other sets.
    # @param other_sets [Array<UnsortedSet, String>] Other sets (as UnsortedSet instances or raw keys)
    # @return [Array] Deserialized members present in any of the sets
    def union(*other_sets)
      keys = extract_keys(other_sets)
      elements = dbclient.sunion(dbkey, *keys)
      deserialize_values(*elements)
    end

    # Returns the difference of this set minus one or more other sets.
    # @param other_sets [Array<UnsortedSet, String>] Other sets (as UnsortedSet instances or raw keys)
    # @return [Array] Deserialized members present in this set but not in any other sets
    def difference(*other_sets)
      keys = extract_keys(other_sets)
      elements = dbclient.sdiff(dbkey, *keys)
      deserialize_values(*elements)
    end
    alias diff difference

    # Checks membership for multiple values at once.
    # @param values [Array] Values to check for membership
    # @return [Array<Boolean>] Array of booleans indicating membership for each value
    def member_any?(*values)
      values = values.flatten
      serialized = values.map { |v| serialize_value(v) }
      dbclient.smismember(dbkey, serialized)
    end
    alias members? member_any?

    # Iterates over set members using cursor-based iteration.
    # @param cursor [Integer] Starting cursor position (default: 0)
    # @param match [String, nil] Optional pattern to filter members
    # @param count [Integer, nil] Optional hint for number of elements to return per call
    # @return [Array<Integer, Array>] Two-element array: [new_cursor, deserialized_members]
    def scan(cursor = 0, match: nil, count: nil)
      opts = {}
      opts[:match] = match if match
      opts[:count] = count if count

      new_cursor, elements = dbclient.sscan(dbkey, cursor, **opts)
      [new_cursor.to_i, deserialize_values(*elements)]
    end

    # Returns the cardinality of the intersection without retrieving members.
    # More memory-efficient than intersection when only the count is needed.
    # @param other_sets [Array<UnsortedSet, String>] Other sets (as UnsortedSet instances or raw keys)
    # @param limit [Integer] Stop counting after reaching this limit (0 = no limit)
    # @return [Integer] Number of elements in the intersection
    def intercard(*other_sets, limit: 0)
      keys = extract_keys(other_sets)
      all_keys = [dbkey, *keys]
      if limit.positive?
        dbclient.sintercard(all_keys.size, *all_keys, limit: limit)
      else
        dbclient.sintercard(all_keys.size, *all_keys)
      end
    end
    alias intersection_cardinality intercard

    # Stores the intersection of this set with other sets into a destination key.
    # @param destination [UnsortedSet, String] Destination set (as UnsortedSet instance or raw key)
    # @param other_sets [Array<UnsortedSet, String>] Other sets to intersect with
    # @return [Integer] Number of elements in the resulting set
    def interstore(destination, *other_sets)
      dest_key = extract_key(destination)
      keys = extract_keys(other_sets)
      result = dbclient.sinterstore(dest_key, dbkey, *keys)
      update_expiration
      result
    end
    alias intersection_store interstore

    # Stores the union of this set with other sets into a destination key.
    # @param destination [UnsortedSet, String] Destination set (as UnsortedSet instance or raw key)
    # @param other_sets [Array<UnsortedSet, String>] Other sets to union with
    # @return [Integer] Number of elements in the resulting set
    def unionstore(destination, *other_sets)
      dest_key = extract_key(destination)
      keys = extract_keys(other_sets)
      result = dbclient.sunionstore(dest_key, dbkey, *keys)
      update_expiration
      result
    end
    alias union_store unionstore

    # Stores the difference of this set minus other sets into a destination key.
    # @param destination [UnsortedSet, String] Destination set (as UnsortedSet instance or raw key)
    # @param other_sets [Array<UnsortedSet, String>] Other sets to subtract
    # @return [Integer] Number of elements in the resulting set
    def diffstore(destination, *other_sets)
      dest_key = extract_key(destination)
      keys = extract_keys(other_sets)
      result = dbclient.sdiffstore(dest_key, dbkey, *keys)
      update_expiration
      result
    end
    alias difference_store diffstore

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

    private

    # Extracts the database key from a set reference.
    # @param set_ref [UnsortedSet, String] An UnsortedSet instance or raw key string
    # @return [String] The database key
    def extract_key(set_ref)
      set_ref.respond_to?(:dbkey) ? set_ref.dbkey : set_ref.to_s
    end

    # Extracts database keys from an array of set references.
    # @param set_refs [Array<UnsortedSet, String>] Array of UnsortedSet instances or raw keys
    # @return [Array<String>] Array of database keys
    def extract_keys(set_refs)
      set_refs.flatten.map { |s| extract_key(s) }
    end

    Familia::DataType.register self, :set
    Familia::DataType.register self, :unsorted_set
  end
end
