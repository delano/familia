# try/features/data_type/sorted_set_zadd_options_try.rb

require_relative '../../helpers/test_helpers'

# Test class for ZADD options testing
class MetricsTest < Familia::Horreum
  identifier_field :name

  field :name
  sorted_set :metrics

  def initialize(name = nil)
    super(name: name || SecureRandom.hex(4))
  end
end

## Store the zset in convenience var
@metricstest = MetricsTest.new('test')
@zset = @metricstest.metrics
#=:> Familia::SortedSet

# ============================================================
# NX Option Tests
# ============================================================

## ZADD NX: Add new element
@zset.clear
@zset.add('member1', 100, nx: true)
#=> true

## ZADD NX: Prevent update of existing element
@zset.add('member1', 200, nx: true)
#=> false

## ZADD NX: Verify score unchanged
@zset.score('member1')
#=> 100.0

## ZADD NX: Allow adding different member
@zset.add('member2', 150, nx: true)
#=> true

# ============================================================
# XX Option Tests
# ============================================================

## ZADD XX: Prevent adding new element
@zset.clear
@zset.add('member1', 100, xx: true)
#=> false

## ZADD XX: Verify element not added
@zset.member?('member1')
#=> false

## ZADD XX: Update existing element
@zset.add('member1', 100)
@zset.add('member1', 200, xx: true)
#=> false

## ZADD XX: Verify score updated
@zset.score('member1')
#=> 200.0

# ============================================================
# GT Option Tests
# ============================================================

## ZADD GT: Allow adding new element
@zset.clear
@zset.add('member1', 100, gt: true)
#=> true

## ZADD GT: Update when new score greater
@zset.add('member1', 200, gt: true)
#=> false

## ZADD GT: Verify score updated
@zset.score('member1')
#=> 200.0

## ZADD GT: Prevent update when new score not greater
@zset.add('member1', 150, gt: true)
#=> false

## ZADD GT: Verify score unchanged
@zset.score('member1')
#=> 200.0

## ZADD GT: Allow update when new score greater again
@zset.add('member1', 300, gt: true)
#=> false

## ZADD GT: Verify score updated again
@zset.score('member1')
#=> 300.0

# ============================================================
# LT Option Tests
# ============================================================

## ZADD LT: Allow adding new element
@zset.clear
@zset.add('member1', 100, lt: true)
#=> true

## ZADD LT: Update when new score lesser
@zset.add('member1', 50, lt: true)
#=> false

## ZADD LT: Verify score updated
@zset.score('member1')
#=> 50.0

## ZADD LT: Prevent update when new score not lesser
@zset.add('member1', 75, lt: true)
#=> false

## ZADD LT: Verify score unchanged
@zset.score('member1')
#=> 50.0

## ZADD LT: Allow update when new score lesser again
@zset.add('member1', 25, lt: true)
#=> false

## ZADD LT: Verify score updated again
@zset.score('member1')
#=> 25.0

# ============================================================
# CH Option Tests
# ============================================================

## ZADD CH: Return count for new element
@zset.clear
@zset.add('member1', 100, ch: true)
#=> true

## ZADD CH: Return count for update (without CH would be 0)
@zset.add('member1', 200, ch: true)
#=> true

## ZADD CH without update: Return 0
@zset.add('member1', 200, ch: true)
#=> false

## ZADD CH with GT: Count changes only
@zset.add('member1', 300, gt: true, ch: true)
#=> true

## ZADD CH with GT: No change when score not greater
@zset.add('member1', 250, gt: true, ch: true)
#=> false

## ZADD CH with LT: Count changes only
@zset.add('member1', 100, lt: true, ch: true)
#=> true

## ZADD CH with LT: No change when score not lesser
@zset.add('member1', 150, lt: true, ch: true)
#=> false

# ============================================================
# Combined Options Tests
# ============================================================

## ZADD XX+GT: Update only if exists and score greater
@zset.clear
@zset.add('member1', 100)
@zset.add('member1', 200, xx: true, gt: true)
#=> false

## ZADD XX+GT: Verify score updated
@zset.score('member1')
#=> 200.0

## ZADD XX+GT: Prevent update when score not greater
@zset.add('member1', 150, xx: true, gt: true)
#=> false

## ZADD XX+GT: Verify score unchanged
@zset.score('member1')
#=> 200.0

## ZADD XX+GT: Prevent adding new element
@zset.add('member2', 500, xx: true, gt: true)
#=> false

## ZADD XX+GT: Verify element not added
@zset.member?('member2')
#=> false

## ZADD XX+LT: Update only if exists and score lesser
@zset.clear
@zset.add('member1', 100)
@zset.add('member1', 50, xx: true, lt: true)
#=> false

## ZADD XX+LT: Verify score updated
@zset.score('member1')
#=> 50.0

## ZADD XX+LT: Prevent update when score not lesser
@zset.add('member1', 75, xx: true, lt: true)
#=> false

## ZADD XX+LT: Verify score unchanged
@zset.score('member1')
#=> 50.0

## ZADD XX+CH: Track updates for existing elements
@zset.clear
@zset.add('member1', 100)
@zset.add('member1', 200, xx: true, ch: true)
#=> true

## ZADD XX+GT+CH: Combined tracking
@zset.add('member1', 300, xx: true, gt: true, ch: true)
#=> true

## ZADD XX+GT+CH: No change when conditions not met
@zset.add('member1', 250, xx: true, gt: true, ch: true)
#=> false

# ============================================================
# Mutual Exclusivity Validation Tests
# ============================================================

## ZADD NX+XX: Raise ArgumentError
@zset.clear
begin
  @zset.add('member1', 100, nx: true, xx: true)
  false
rescue ArgumentError => e
  e.message.include?('mutually exclusive')
end
#=> true

## ZADD GT+LT: Raise ArgumentError
begin
  @zset.add('member1', 100, gt: true, lt: true)
  false
rescue ArgumentError => e
  e.message.include?('mutually exclusive')
end
#=> true

## ZADD NX+GT: Raise ArgumentError
begin
  @zset.add('member1', 100, nx: true, gt: true)
  false
rescue ArgumentError => e
  e.message.include?('mutually exclusive')
end
#=> true

## ZADD NX+LT: Raise ArgumentError
begin
  @zset.add('member1', 100, nx: true, lt: true)
  false
rescue ArgumentError => e
  e.message.include?('mutually exclusive')
end
#=> true

# ============================================================
# Backward Compatibility Tests
# ============================================================

## ZADD: No options specified (default behavior)
@zset.clear
@zset.add('member1', 100)
#=> true

## ZADD: Update without options
@zset.add('member1', 200)
#=> false

## ZADD: Verify score updated
@zset.score('member1')
#=> 200.0

## ZADD: Verify default score (Familia.now)
@zset.clear
@zset.add('member2')
@zset.score('member2') > 0
#=> true

# ============================================================
# Serialization Integration Tests
# ============================================================

## ZADD with symbol values and NX
@zset.clear
@zset.add(:member1, 100, nx: true)
#=> true

## ZADD with symbol values: Verify membership
@zset.member?(:member1)
#=> true

## ZADD with symbol values: NX prevents update
@zset.add(:member1, 200, nx: true)
#=> false

## ZADD with symbol values: XX updates
@zset.add(:member1, 300, xx: true)
#=> false

## ZADD with symbol values: Verify score
@zset.score(:member1)
#=> 300.0

## ZADD with object values and NX
@metrics_test3 = MetricsTest.new('object_value_test')
@zset.add(@metrics_test3, 100, nx: true)
#=> true

## ZADD with object values: Verify membership
@zset.member?(@metrics_test3)
#=> true

# ============================================================
# Edge Cases
# ============================================================

## ZADD with nil score defaults to Familia.now (NX option)
@zset.clear
result = @zset.add('member1', nil, nx: true)
result == true && @zset.score('member1') > 0
#=> true

## ZADD with nil score defaults to Familia.now (XX option)
@zset.add('member2', 100)
result = @zset.add('member2', nil, xx: true)
result == false && @zset.score('member2') > 100
#=> true

## ZADD GT with equal score: No update
@zset.clear
@zset.add('member1', 100)
@zset.add('member1', 100, gt: true)
#=> false

## ZADD LT with equal score: No update
@zset.clear
@zset.add('member1', 100)
@zset.add('member1', 100, lt: true)
#=> false

## ZADD NX with CH: Return count correctly
@zset.clear
@zset.add('member1', 100, nx: true, ch: true)
#=> true

## ZADD NX with CH: Return 0 when exists
@zset.add('member1', 200, nx: true, ch: true)
#=> false
