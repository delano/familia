# Time Utilities Guide

Familia provides a comprehensive time utilities refinement that adds convenient time conversion and age calculation methods to Ruby's `Numeric` and `String` classes.

## Overview

The `Familia::Refinements::TimeLiterals` module extends Ruby's built-in classes with intuitive time manipulation methods:

```ruby
using Familia::Refinements::TimeLiterals

2.hours        #=> 7200 (seconds)
"30m".in_seconds  #=> 1800
timestamp.days_old  #=> 5.2
```

## Time Constants

Familia uses **Gregorian year** calculations for consistent time conversions:

```ruby
PER_YEAR  = 31_556_952.0  # 365.2425 days (accounts for leap years)
PER_MONTH = 2_629_746.0   # PER_YEAR / 12 (30.437 days)
PER_WEEK  = 604_800.0     # 7 days
PER_DAY   = 86_400.0      # 24 hours
```

### Why Gregorian Year?

The key design decision ensures **mathematical consistency**:

```ruby
12.months == 1.year  #=> true (both equal 31,556,952 seconds)
```

This prevents subtle bugs where `12.months` and `1.year` would differ by ~5.8 hours.

## Basic Time Conversions

### Converting Numbers to Time Units

```ruby
using Familia::Refinements::TimeLiterals

# Singular and plural forms work identically
1.second   #=> 1
30.seconds #=> 30
5.minutes  #=> 300
2.hours    #=> 7200
3.days     #=> 259200
1.week     #=> 604800
2.months   #=> 5259492
1.year     #=> 31556952
```

### Converting Time Units Back

```ruby
7200.in_hours     #=> 2.0
259200.in_days    #=> 3.0
5259492.in_months #=> 2.0
31556952.in_years #=> 1.0
```

## String Time Parsing

Parse human-readable time strings:

```ruby
"30s".in_seconds    #=> 30.0
"5m".in_seconds     #=> 300.0
"2h".in_seconds     #=> 7200.0
"1d".in_seconds     #=> 86400.0
"1w".in_seconds     #=> 604800.0
"2mo".in_seconds    #=> 5259492.0
"1y".in_seconds     #=> 31556952.0
```

### Supported String Formats

| Unit | Abbreviations | Example |
|------|---------------|---------|
| Microseconds | `us`, `μs`, `microsecond`, `microseconds` | `"500us"` |
| Milliseconds | `ms`, `millisecond`, `milliseconds` | `"250ms"` |
| Seconds | `s`, `second`, `seconds` | `"30s"` |
| Minutes | `m`, `minute`, `minutes` | `"15m"` |
| Hours | `h`, `hour`, `hours` | `"2h"` |
| Days | `d`, `day`, `days` | `"7d"` |
| Weeks | `w`, `week`, `weeks` | `"2w"` |
| Months | `mo`, `month`, `months` | `"6mo"` |
| Years | `y`, `year`, `years` | `"1y"` |

**Note**: Use `"mo"` for months to avoid confusion with `"m"` (minutes).

## Age Calculations

Calculate how old timestamps are:

```ruby
# Basic age calculation
old_timestamp = 2.days.ago.to_i
old_timestamp.age_in(:days)    #=> ~2.0
old_timestamp.age_in(:hours)   #=> ~48.0
old_timestamp.age_in(:months)  #=> ~0.066

# Convenience methods
old_timestamp.days_old     #=> ~2.0
old_timestamp.hours_old    #=> ~48.0
old_timestamp.minutes_old  #=> ~2880.0
old_timestamp.weeks_old    #=> ~0.28
old_timestamp.months_old   #=> ~0.066
old_timestamp.years_old    #=> ~0.005

# Calculate age from specific reference time
past_timestamp = 1.week.ago.to_i
reference_time = 3.days.ago
past_timestamp.age_in(:days, reference_time)  #=> ~4.0
```

## Time Comparisons

```ruby
timestamp = 2.hours.ago.to_i

# Check if older than duration
timestamp.older_than?(1.hour)   #=> true
timestamp.older_than?(3.hours)  #=> false

# Check if newer than duration (future)
future_timestamp = 1.hour.from_now.to_i
future_timestamp.newer_than?(30.minutes)  #=> true

# Check if within duration of now (past or future)
timestamp.within?(3.hours)      #=> true
timestamp.within?(1.hour)       #=> false
```

## Practical Examples

### Cache Expiration

```ruby
using Familia::Refinements::TimeLiterals

class CacheEntry < Familia::Horreum
  field :data
  field :created_at

  def expired?
    created_at.to_i.older_than?(1.hour)
  end

  def cache_age
    created_at.to_i.minutes_old
  end
end
```

### Session Management

```ruby
class UserSession < Familia::Horreum
  field :last_active

  def stale?
    last_active.to_i.older_than?(30.minutes)
  end

  def session_duration
    "Active for #{last_active.to_i.hours_old.round(1)} hours"
  end
end
```

### Data Retention

```ruby
def cleanup_old_logs
  Log.all.select do |log|
    log.timestamp.to_i.older_than?(30.days)
  end.each(&:destroy)
end
```

## Important Notes

### Calendar vs. Precise Time

Familia's time utilities use **average durations** suitable for:
- Age calculations
- Cache expiration
- Time-based cleanup
- General time arithmetic

For **calendar-aware operations** (exact months, leap years), use Ruby's `Date`/`Time` classes:

```ruby
# For average durations (Familia)
user_age = signup_date.to_i.months_old  #=> 6.2

# For exact calendar operations (Ruby stdlib)
exact_months = Date.today.months_since(signup_date)  #=> 6
```

### Thread Safety

All time utility methods are thread-safe and work with frozen objects.

## Migration from v1.x

If upgrading from earlier versions:

```ruby
# Old behavior (inconsistent)
12.months != 1.year  # Different values

# New behavior (consistent)
12.months == 1.year  # Same value: 31,556,952 seconds
```

Update any code that relied on the old 365-day year constant to expect the new Gregorian year values.
