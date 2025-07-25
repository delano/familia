# lib/familia/datatype/types/list.rb

module Familia
  class List < DataType

    # Returns the number of elements in the list
    # @return [Integer] number of elements
    def element_count
      dbclient.llen dbkey
    end
    alias size element_count

    def empty?
      element_count.zero?
    end

    def push *values
      echo :push, caller(1..1).first if Familia.debug
      values.flatten.compact.each { |v| dbclient.rpush dbkey, serialize_value(v) }
      dbclient.ltrim dbkey, -@opts[:maxlength], -1 if @opts[:maxlength]
      update_expiration
      self
    end
    alias append push

    def <<(val)
      push val
    end
    alias add <<

    def unshift *values
      values.flatten.compact.each { |v| dbclient.lpush dbkey, serialize_value(v) }
      # TODO: test maxlength
      dbclient.ltrim dbkey, 0, @opts[:maxlength] - 1 if @opts[:maxlength]
      update_expiration
      self
    end
    alias prepend unshift

    def pop
      deserialize_value dbclient.rpop(dbkey)
    end

    def shift
      deserialize_value dbclient.lpop(dbkey)
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
      echo :members, caller(1..1).first if Familia.debug
      count -= 1 if count.positive?
      range 0, count
    end
    alias all members
    alias to_a members

    def membersraw(count = -1)
      count -= 1 if count.positive?
      rangeraw 0, count
    end

    def each(&blk)
      range.each(&blk)
    end

    def each_with_index(&blk)
      range.each_with_index(&blk)
    end

    def eachraw(&blk)
      rangeraw.each(&blk)
    end

    def eachraw_with_index(&blk)
      rangeraw.each_with_index(&blk)
    end

    def collect(&blk)
      range.collect(&blk)
    end

    def select(&blk)
      range.select(&blk)
    end

    def collectraw(&blk)
      rangeraw.collect(&blk)
    end

    def selectraw(&blk)
      rangeraw.select(&blk)
    end

    def at(idx)
      deserialize_value dbclient.lindex(dbkey, idx)
    end

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
  end
end
