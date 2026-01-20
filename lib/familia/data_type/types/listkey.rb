# lib/familia/data_type/types/listkey.rb
#
# frozen_string_literal: true

module Familia
  class ListKey < DataType
    # Returns the number of elements in the list
    # @return [Integer] number of elements
    def element_count
      dbclient.llen dbkey
    end
    alias size element_count
    alias length element_count
    alias count element_count

    def empty?
      element_count.zero?
    end

    def push *values
      echo :push, Familia.pretty_stack(limit: 1) if Familia.debug
      values.flatten.compact.each { |v| dbclient.rpush dbkey, serialize_value(v) }
      dbclient.ltrim dbkey, -@opts[:maxlength], -1 if @opts[:maxlength]
      update_expiration
      self
    end
    alias append push

    def <<(val)
      push(val)
    end
    alias add_element <<
    alias add <<

    def unshift *values
      values.flatten.compact.each { |v| dbclient.lpush dbkey, serialize_value(v) }
      # TODO: test maxlength
      dbclient.ltrim dbkey, 0, @opts[:maxlength] - 1 if @opts[:maxlength]
      update_expiration
      self
    end
    alias prepend unshift

    # Removes and returns the last element(s) from the list
    # @param count [Integer, nil] Number of elements to pop (Redis 6.2+)
    # @return [Object, Array<Object>, nil] Single element or array if count specified
    def pop(count = nil)
      if count
        result = dbclient.rpop(dbkey, count)
        return nil if result.nil?

        deserialize_values(*result)
      else
        deserialize_value dbclient.rpop(dbkey)
      end
    end

    # Removes and returns the first element(s) from the list
    # @param count [Integer, nil] Number of elements to shift (Redis 6.2+)
    # @return [Object, Array<Object>, nil] Single element or array if count specified
    def shift(count = nil)
      if count
        result = dbclient.lpop(dbkey, count)
        return nil if result.nil?

        deserialize_values(*result)
      else
        deserialize_value dbclient.lpop(dbkey)
      end
    end

    def [](idx, count = nil)
      if idx.is_a? Range
        range idx.first, idx.last
      elsif count
        case count <=> 0
        when 1  then range(idx, idx + count - 1)
        when 0  then []
        when -1 then nil
        end
      else
        at idx
      end
    end
    alias slice []

    def member?(value)
      !dbclient.lpos(dbkey, serialize_value(value)).nil?
    end

    # Removes elements equal to value from the list
    # @param value The value to remove
    # @param count [Integer] Number of elements to remove (0 means all)
    # @return [Integer] The number of removed elements
    def remove_element(value, count = 0)
      dbclient.lrem dbkey, count, serialize_value(value)
    end
    alias remove remove_element

    def range(sidx = 0, eidx = -1)
      elements = rangeraw sidx, eidx
      deserialize_values(*elements)
    end

    def rangeraw(sidx = 0, eidx = -1)
      dbclient.lrange(dbkey, sidx, eidx)
    end

    def members(count = -1)
      echo :members, Familia.pretty_stack(limit: 1) if Familia.debug
      count -= 1 if count.positive?
      range 0, count
    end
    alias all members
    alias to_a members

    def membersraw(count = -1)
      count -= 1 if count.positive?
      rangeraw 0, count
    end

    def each(&)
      range.each(&)
    end

    def each_with_index(&)
      range.each_with_index(&)
    end

    def eachraw(&)
      rangeraw.each(&)
    end

    def eachraw_with_index(&)
      rangeraw.each_with_index(&)
    end

    def collect(&)
      range.collect(&)
    end

    def select(&)
      range.select(&)
    end

    def collectraw(&)
      rangeraw.collect(&)
    end

    def selectraw(&)
      rangeraw.select(&)
    end

    def at(idx)
      deserialize_value dbclient.lindex(dbkey, idx)
    end

    # Trims the list to the specified range
    # @param start [Integer] Start index (0-based, negative counts from end)
    # @param stop [Integer] End index (inclusive, negative counts from end)
    # @return [String] "OK" on success
    def trim(start, stop)
      dbclient.ltrim dbkey, start, stop
    end
    alias ltrim trim

    # Sets the element at the specified index
    # @param index [Integer] Index to set (0-based, negative counts from end)
    # @param value The value to set
    # @return [String] "OK" on success
    # @raise [Redis::CommandError] if index is out of range
    def set(index, value)
      result = dbclient.lset dbkey, index, serialize_value(value)
      update_expiration
      result
    end
    alias lset set

    # Inserts an element before or after a pivot element
    # @param position [:before, :after] Where to insert relative to pivot
    # @param pivot The pivot element to search for
    # @param value The value to insert
    # @return [Integer] Length of list after insert, or -1 if pivot not found
    def insert(position, pivot, value)
      pos = case position
            when :before, 'BEFORE' then 'BEFORE'
            when :after, 'AFTER' then 'AFTER'
            else
              raise ArgumentError, "position must be :before or :after, got #{position.inspect}"
            end
      result = dbclient.linsert dbkey, pos, serialize_value(pivot), serialize_value(value)
      update_expiration if result.positive?
      result
    end
    alias linsert insert

    # Moves an element from this list to another list atomically
    # @param destination [ListKey, String] Destination list (ListKey or key string)
    # @param wherefrom [:left, :right] Which end to pop from source
    # @param whereto [:left, :right] Which end to push to destination
    # @return [Object, nil] The moved element, or nil if source is empty
    def move(destination, wherefrom, whereto)
      dest_key = destination.respond_to?(:dbkey) ? destination.dbkey : destination
      from = wherefrom.to_s.upcase
      to = whereto.to_s.upcase

      unless %w[LEFT RIGHT].include?(from) && %w[LEFT RIGHT].include?(to)
        raise ArgumentError, 'wherefrom and whereto must be :left or :right'
      end

      result = dbclient.lmove dbkey, dest_key, from, to
      deserialize_value result
    end
    alias lmove move

    # Pushes values only if the list already exists
    # @param values Values to push to the tail of the list
    # @return [Integer] Length of list after push, or 0 if list doesn't exist
    def pushx(*values)
      return 0 if values.empty?

      result = values.flatten.compact.reduce(0) do |len, v|
        dbclient.rpushx dbkey, serialize_value(v)
      end
      update_expiration if result.positive?
      result
    end
    alias rpushx pushx

    # Pushes values to the head only if the list already exists
    # @param values Values to push to the head of the list
    # @return [Integer] Length of list after push, or 0 if list doesn't exist
    def unshiftx(*values)
      return 0 if values.empty?

      result = values.flatten.compact.reduce(0) do |len, v|
        dbclient.lpushx dbkey, serialize_value(v)
      end
      update_expiration if result.positive?
      result
    end
    alias lpushx unshiftx

    def first
      at 0
    end

    def last
      at(-1)
    end

    # TODO: def replace
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

    Familia::DataType.register self, :list
    Familia::DataType.register self, :listkey
  end
end
