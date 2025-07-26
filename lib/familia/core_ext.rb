# lib/familia/core_ext.rb

# Extends the String class with time-related functionality
#
# This implementaton assumes Time::Units and Numeric mixins are available.
#
class String
  # Converts a string representation of time to seconds
  #
  # @example
  #   "60m".in_seconds #=> 3600.0
  #
  # @return [Float, nil] The time in seconds, or nil if the string is invalid
  def in_seconds
    q, u = scan(/([\d.]+)([smhyd])?/).flatten
    q &&= q.to_f and u ||= 's'
    q&.in_seconds(u)
  end
end

# Extends the Time class with additional time unit functionality
class Time
  # Provides methods for working with various time units
  module Units
    # rubocop:disable Style/SingleLineMethods, Layout/ExtraSpacing

    PER_MICROSECOND = 0.000001
    PER_MILLISECOND = 0.001
    PER_MINUTE = 60.0
    PER_HOUR = 3600.0
    PER_DAY = 86_400.0

    # Conversion methods
    #
    # From other time units -> seconds
    #
    def microseconds()    seconds * PER_MICROSECOND     end
    def milliseconds()    seconds * PER_MILLISECOND    end
    def seconds()         self                         end
    def minutes()         seconds * PER_MINUTE          end
    def hours()           seconds * PER_HOUR             end
    def days()            seconds * PER_DAY               end
    def weeks()           seconds * PER_DAY * 7           end
    def years()           seconds * PER_DAY * 365        end

    # From seconds -> other time units
    #
    def in_years()        seconds / PER_DAY / 365      end
    def in_weeks()        seconds / PER_DAY / 7       end
    def in_days()         seconds / PER_DAY          end
    def in_hours()        seconds / PER_HOUR          end
    def in_minutes()      seconds / PER_MINUTE         end
    def in_milliseconds() seconds / PER_MILLISECOND    end
    def in_microseconds() seconds / PER_MICROSECOND   end

    #
    # Converts seconds to a Time object
    #
    # @return [Time] A Time object representing the seconds
    def in_time
      Time.at(self).utc
    end

    # Converts seconds to the specified time unit
    #
    # @param u [String, Symbol] The unit to convert to (e.g., 'y', 'w', 'd', 'h', 'm', 'ms', 'us')
    # @return [Float] The converted time value
    def in_seconds(u = nil)
      case u.to_s
      when /\A(y)|(years?)\z/
        years
      when /\A(w)|(weeks?)\z/
        weeks
      when /\A(d)|(days?)\z/
        days
      when /\A(h)|(hours?)\z/
        hours
      when /\A(m)|(minutes?)\z/
        minutes
      when /\A(ms)|(milliseconds?)\z/
        milliseconds
      when /\A(us)|(microseconds?)|(μs)\z/
        microseconds
      else
        self
      end
    end

    # Starring Jennifer Garner, Victor Garber, and Carl Lumbly
    alias ms milliseconds
    alias μs microseconds
    alias second seconds
    alias minute minutes
    alias hour hours
    alias day days
    alias week weeks
    alias year years

    # rubocop:enable Style/SingleLineMethods, Layout/ExtraSpacing
  end
end

# Extends the Numeric class with time unit and byte conversion functionality
class Numeric
  include Time::Units

  # Converts the number to milliseconds
  #
  # @return [Float] The number in milliseconds
  def to_ms
    (self * 1000.to_f)
  end

  # Converts the number to a human-readable byte representation using binary units
  #
  # @return [String] A string representing the number in bytes, KiB, MiB, GiB, or TiB
  #
  # @example
  #   1024.to_bytes      #=> "1.00 KiB"
  #   2_097_152.to_bytes #=> "2.00 MiB"
  #   3_221_225_472.to_bytes #=> "3.00 GiB"
  #
  def to_bytes
    units = %w[B KiB MiB GiB TiB]
    size = abs.to_f
    unit = 0

    while size >= 1024 && unit < units.length - 1
      size /= 1024
      unit += 1
    end

    format('%3.2f %s', size, units[unit])
  end
end
