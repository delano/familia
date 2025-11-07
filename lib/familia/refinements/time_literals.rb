# lib/familia/refinements/time_literals.rb
#
# frozen_string_literal: true

module Familia
  module Refinements
    # Familia::Refinements::TimeLiterals
    #
    # This module provides a set of refinements for `Numeric` and `String` to
    # enable readable and expressive time duration and timestamp manipulation.
    #
    # The name "TimeLiterals" reflects its core purpose: to allow us to treat
    # numeric values directly as "literals" of time units (e.g., `5.minutes`,
    # `1.day`). It extends this concept to include conversions between these
    # literal time quantities, parsing string representations of time
    # durations, and performing common timestamp-based calculations
    # in an intuitive manner.
    #
    # @example Expressing durations
    #   5.minutes.ago           #=> A Time object 5 minutes in the past
    #   1.day.from_now          #=> A Time object 1 day in the future
    #   (2.5).hours             #=> 9000.0 (seconds)
    #
    # @example Converting between units
    #   3600.in_hours           #=> 1.0
    #   86400.in_days           #=> 1.0
    #
    # @example Parsing string durations
    #   "30m".in_seconds        #=> 1800.0
    #   "2.5h".in_seconds       #=> 9000.0
    #
    # @example Timestamp calculations
    #   timestamp = 2.days.ago.to_i
    #   timestamp.days_old      #=> ~2.0
    #   timestamp.older_than?(1.day) #=> true
    #
    # @note `to_bytes` also lives here until we find it a better home!
    #
    module TimeLiterals
      # Time unit constants
      PER_MICROSECOND = 0.000001
      PER_MILLISECOND = 0.001
      PER_MINUTE      = 60.0
      PER_HOUR        = 3600.0
      PER_DAY         = 86_400.0
      PER_WEEK        = 604_800.0
      PER_YEAR        = 31_556_952.0 # 365.2425 days (Gregorian year)
      PER_MONTH       = PER_YEAR / 12.0 # 30.437 days (consistent with Gregorian year)

      UNIT_METHODS = {
        'y' => :years,
        'year' => :years,
        'years' => :years,
        'mo' => :months,
        'month' => :months,
        'months' => :months,
        'w' => :weeks,
        'week' => :weeks,
        'weeks' => :weeks,
        'd' => :days,
        'day' => :days,
        'days' => :days,
        'h' => :hours,
        'hour' => :hours,
        'hours' => :hours,
        'm' => :minutes,
        'minute' => :minutes,
        'minutes' => :minutes,
        'ms' => :milliseconds,
        'millisecond' => :milliseconds,
        'milliseconds' => :milliseconds,
        'us' => :microseconds,
        'microsecond' => :microseconds,
        'microseconds' => :microseconds,
        'μs' => :microseconds,
      }.freeze

      # Shared conversion logic
      def self.convert_to_seconds(value, unit)
        case UNIT_METHODS.fetch(unit.to_s.downcase, nil)
        when :milliseconds then value * PER_MILLISECOND
        when :microseconds then value * PER_MICROSECOND
        when :minutes then value * PER_MINUTE
        when :hours then value * PER_HOUR
        when :days then value * PER_DAY
        when :weeks then value * PER_WEEK
        when :months then value * PER_MONTH
        when :years then value * PER_YEAR
        else value
        end
      end

      module NumericMethods
        def microseconds = seconds * PER_MICROSECOND
        def milliseconds = seconds * PER_MILLISECOND
        def seconds      = self
        def minutes      = seconds * PER_MINUTE
        def hours        = seconds * PER_HOUR
        def days         = seconds * PER_DAY
        def weeks        = seconds * PER_WEEK
        def months       = seconds * PER_MONTH
        def years        = seconds * PER_YEAR

        # Aliases with singular forms
        def microsecond = microseconds
        def millisecond = milliseconds
        def second = seconds
        def minute = minutes
        def hour = hours
        def day = days
        def week = weeks
        def month = months
        def year = years

        # Shortest aliases
        def ms = milliseconds
        def μs = microseconds

        # Seconds -> other time units
        def in_years        = seconds / PER_YEAR
        def in_months       = seconds / PER_MONTH
        def in_weeks        = seconds / PER_WEEK
        def in_days         = seconds / PER_DAY
        def in_hours        = seconds / PER_HOUR
        def in_minutes      = seconds / PER_MINUTE
        def in_milliseconds = seconds / PER_MILLISECOND
        def in_microseconds = seconds / PER_MICROSECOND
        def in_seconds      = seconds # for semantic purposes

        # Time manipulation
        def ago          = Familia.now - seconds
        def from_now     = Familia.now + seconds
        def before(time) = time - seconds
        def after(time)  = time + seconds
        def in_time = Time.at(seconds).utc

        # Milliseconds conversion
        def to_ms = seconds * 1000.0

        # Converts seconds to specified time unit
        #
        # @param unit [String, Symbol] Unit to convert to
        # @return [Float] Converted time value
        def in_seconds(unit = nil)
          unit ? TimeLiterals.convert_to_seconds(self, unit) : self
        end

        # Converts the number to a human-readable string representation
        #
        # @return [String] A formatted string e.g. "1 day" or "10 seconds"
        #
        # @example
        #   10.to_humanize #=> "10 seconds"
        #   60.to_humanize #=> "1 minute"
        #   3600.to_humanize #=> "1 hour"
        #   86400.to_humanize #=> "1 day"
        def humanize
          gte_zero = positive? || zero?
          duration = (gte_zero ? self : abs) # let's keep it positive up in here
          text = case (num = duration.to_i)
                 in 0..59 then "#{num} second#{'s' if num != 1}"
                 in 60..3599 then "#{num /= 60} minute#{'s' if num != 1}"
                 in 3600..86_399 then "#{num /= 3600} hour#{'s' if num != 1}"
                 else "#{num /= 86_400} day#{'s' if num != 1}"
                 end
          gte_zero ? text : "#{text} ago"
        end

        # Converts the number to a human-readable byte representation using binary units
        #
        # @return [String] A formatted string of bytes, KiB, MiB, GiB, or TiB
        #
        # @example
        #   1024.to_bytes      #=> "1.00 KiB"
        #   2_097_152.to_bytes #=> "2.00 MiB"
        #   3_221_225_472.to_bytes #=> "3.00 GiB"
        #
        def to_bytes
          units = %w[B KiB MiB GiB TiB]
          size  = abs.to_f
          unit  = 0

          while size >= 1024 && unit < units.length - 1
            size /= 1024
            unit += 1
          end

          format('%3.2f %s', size, units[unit])
        end

        # Calculates age of timestamp in specified unit from reference time
        #
        # @param unit [String, Symbol] Time unit ('days', 'hours', 'minutes', 'weeks')
        # @param from_time [Time, nil] Reference time (defaults to Familia.now)
        # @return [Float] Age in specified unit
        # @example
        #   timestamp = 2.days.ago.to_i
        #   timestamp.age_in(:days)         #=> ~2.0
        #   timestamp.age_in('hours')       #=> ~48.0
        #   timestamp.age_in(:days, 1.day.ago) #=> ~1.0
        def age_in(unit, from_time = nil)
          from_time ||= Familia.now
          age_seconds = from_time.to_f - to_f
          case UNIT_METHODS.fetch(unit.to_s.downcase, nil)
          when :days then age_seconds / PER_DAY
          when :hours then age_seconds / PER_HOUR
          when :minutes then age_seconds / PER_MINUTE
          when :weeks then age_seconds / PER_WEEK
          when :months then age_seconds / PER_MONTH
          when :years then age_seconds / PER_YEAR
          else age_seconds
          end
        end

        # Convenience methods for `age_in(unit)` calls.
        #
        # @param from_time [Time, nil] Reference time (defaults to Familia.now)
        # @return [Float] Age in days
        # @example
        #   timestamp.days_old    #=> 2.5
        def days_old(*) = age_in(:days, *)
        def hours_old(*) = age_in(:hours, *)
        def minutes_old(*) = age_in(:minutes, *)
        def weeks_old(*) = age_in(:weeks, *)
        def months_old(*) = age_in(:months, *)
        def years_old(*) = age_in(:years, *)

        # Checks if timestamp is older than specified duration in seconds
        #
        # @param duration [Numeric] Duration in seconds to compare against
        # @return [Boolean] true if timestamp is older than duration
        # @note Both older_than? and newer_than? can return false when timestamp
        #   is within the same second. Use within? to check this case.
        #
        # @example
        #   Familia.now.older_than?(1.second)    #=> false
        def older_than?(duration)
          self < (Familia.now - duration)
        end

        # Checks if timestamp is newer than specified duration in the future
        #
        # @example
        #   Familia.now.newer_than?(1.second)    #=> false
        def newer_than?(duration)
          self > (Familia.now + duration)
        end

        # Checks if timestamp is within specified duration of now (past or future)
        #
        # @param duration [Numeric] Duration in seconds to compare against
        # @return [Boolean] true if timestamp is within duration of now
        # @example
        #   30.minutes.ago.to_i.within?(1.hour)     #=> true
        #   30.minutes.from_now.to_i.within?(1.hour) #=> true
        #   2.hours.ago.to_i.within?(1.hour)        #=> false
        def within?(duration)
          (self - Familia.now).abs <= duration
        end
      end

      module StringMethods
        # Converts string time representation to seconds
        #
        # @example
        #   "60m".in_seconds #=> 3600.0
        #   "2.5h".in_seconds #=> 9000.0
        #   "1y".in_seconds #=> 31536000.0
        #
        # @return [Float, nil] Time in seconds or nil if invalid
        def in_seconds
          quantity, unit = scan(/([\d.]+)([a-zA-Zμs]+)?/).flatten
          return nil unless quantity

          quantity = quantity.to_f
          unit ||= 's'
          TimeLiterals.convert_to_seconds(quantity, unit)
        end
      end

      refine ::Numeric do
        import_methods NumericMethods
      end
      refine ::String do
        import_methods StringMethods
      end
    end
  end
end
