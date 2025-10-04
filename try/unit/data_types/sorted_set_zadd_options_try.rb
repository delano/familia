# try/features/data_type/sorted_set_zadd_options_try.rb

require_relative '../../support/helpers/test_helpers'

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

# ============================================================
# Multiple Elements Tests (Redis 6.2+ ZADD behavior)
# ============================================================

## Multiple elements: Add multiple elements at once (simulate with array)
@zset.clear
result1 = @zset.add('member1', 100)
result2 = @zset.add('member2', 200)
[result1, result2]
#=> [true, true]

## Multiple elements: Verify both elements exist
[@zset.member?('member1'), @zset.member?('member2')]
#=> [true, true]

## Multiple elements: Update one existing, add one new (simulate)
result1 = @zset.add('member1', 150)  # update existing
result2 = @zset.add('member3', 300)  # add new
[result1, result2]
#=> [false, true]

## Multiple elements with CH: Track all changes (simulate behavior)
@zset.clear
@zset.add('member1', 100)  # existing element
result1 = @zset.add('member1', 150, ch: true)  # update existing
result2 = @zset.add('member2', 200, ch: true)  # add new
[result1, result2]
#=> [true, true]

## Multiple elements with CH: No changes
result1 = @zset.add('member1', 150, ch: true)  # same score
result2 = @zset.add('member2', 200, ch: true)  # same score
[result1, result2]
#=> [false, false]

## Multiple elements with NX: Mixed new and existing
@zset.clear
@zset.add('member1', 100)  # pre-existing
result1 = @zset.add('member1', 150, nx: true)  # existing, should not update
result2 = @zset.add('member2', 200, nx: true)  # new, should add
[result1, result2]
#=> [false, true]

## Multiple elements with NX: Verify scores unchanged for existing
@zset.score('member1')
#=> 100.0

## Multiple elements with NX: Verify new element added
@zset.score('member2')
#=> 200.0

## Multiple elements with XX: Mixed existing and new
@zset.clear
@zset.add('member1', 100)  # pre-existing
result1 = @zset.add('member1', 150, xx: true)  # existing, should update
result2 = @zset.add('member2', 200, xx: true)  # new, should not add
[result1, result2]
#=> [false, false]

## Multiple elements with XX: Verify existing updated
@zset.score('member1')
#=> 150.0

## Multiple elements with XX: Verify new element not added
@zset.member?('member2')
#=> false

## Multiple elements with GT: Mixed score conditions
@zset.clear
@zset.add('member1', 100)
@zset.add('member2', 200)
result1 = @zset.add('member1', 150, gt: true)  # 150 > 100, should update
result2 = @zset.add('member2', 150, gt: true)  # 150 < 200, should not update
[result1, result2]
#=> [false, false]

## Multiple elements with GT: Verify selective updates
[@zset.score('member1'), @zset.score('member2')]
#=> [150.0, 200.0]

## Multiple elements with LT: Mixed score conditions
@zset.clear
@zset.add('member1', 100)
@zset.add('member2', 200)
result1 = @zset.add('member1', 150, lt: true)  # 150 > 100, should not update
result2 = @zset.add('member2', 150, lt: true)  # 150 < 200, should update
[result1, result2]
#=> [false, false]

## Multiple elements with LT: Verify selective updates
[@zset.score('member1'), @zset.score('member2')]
#=> [100.0, 150.0]

## Multiple elements with XX+CH: Track updates only
@zset.clear
@zset.add('member1', 100)
@zset.add('member2', 200)
result1 = @zset.add('member1', 150, xx: true, ch: true)  # existing, updated
result2 = @zset.add('member3', 300, xx: true, ch: true)  # new, not added
[result1, result2]
#=> [true, false]

## Multiple elements with XX+GT+CH: Complex conditions
@zset.clear
@zset.add('member1', 100)
@zset.add('member2', 200)
result1 = @zset.add('member1', 150, xx: true, gt: true, ch: true)  # update: 150 > 100
result2 = @zset.add('member2', 150, xx: true, gt: true, ch: true)  # no update: 150 < 200
[result1, result2]
#=> [true, false]

## Multiple elements with NX+CH: Only new elements tracked
@zset.clear
@zset.add('member1', 100)
result1 = @zset.add('member1', 150, nx: true, ch: true)  # existing, no change
result2 = @zset.add('member2', 200, nx: true, ch: true)  # new, added
[result1, result2]
#=> [false, true]

# ============================================================
# Large Batch Operations Simulation
# ============================================================

## Batch operation: Add multiple elements with different options
@zset.clear
batch_results = []
5.times do |i|
  member = "member#{i}"
  score = (i + 1) * 100
  result = @zset.add(member, score, ch: true)
  batch_results << result
end
batch_results
#=> [true, true, true, true, true]

## Batch operation: Update all with GT option
update_results = []
5.times do |i|
  member = "member#{i}"
  new_score = (i + 1) * 100 + 50  # Increase all scores
  result = @zset.add(member, new_score, gt: true, ch: true)
  update_results << result
end
update_results
#=> [true, true, true, true, true]

## Batch operation: Try to decrease all with GT (should fail)
decrease_results = []
5.times do |i|
  member = "member#{i}"
  new_score = (i + 1) * 100 + 25  # Lower than current
  result = @zset.add(member, new_score, gt: true, ch: true)
  decrease_results << result
end
decrease_results
#=> [false, false, false, false, false]

## Batch operation: Mixed NX operations on existing set
mixed_results = []
# Try to add existing members (should fail with NX)
3.times do |i|
  member = "member#{i}"
  result = @zset.add(member, 999, nx: true, ch: true)
  mixed_results << result
end
# Try to add new members (should succeed with NX)
2.times do |i|
  member = "new_member#{i}"
  result = @zset.add(member, 999, nx: true, ch: true)
  mixed_results << result
end
mixed_results
#=> [false, false, false, true, true]

# ============================================================
# Explicit Return Value Verification Tests
# ============================================================

## Return value: Add new element (should return true)
@zset.clear
@zset.add('member1', 100)
#=> true

## Return value: Update existing element (should return false)
@zset.add('member1', 200)
#=> false

## Return value: Add with NX for new element (should return true)
@zset.add('member2', 100, nx: true)
#=> true

## Return value: Add with NX for existing element (should return false)
@zset.add('member2', 200, nx: true)
#=> false

## Return value: Add with XX for non-existing element (should return false)
@zset.clear
@zset.add('member1', 100, xx: true)
#=> false

## Return value: Add with XX for existing element update (should return false)
@zset.add('member1', 100)
@zset.add('member1', 200, xx: true)
#=> false

## Return value: Add with CH for new element (should return true)
@zset.clear
@zset.add('member1', 100, ch: true)
#=> true

## Return value: Add with CH for element update (should return true)
@zset.add('member1', 200, ch: true)
#=> true

## Return value: Add with CH for no change (should return false)
@zset.add('member1', 200, ch: true)
#=> false

## Return value: Add with GT for new element (should return true)
@zset.clear
@zset.add('member1', 100, gt: true)
#=> true

## Return value: Add with GT for score increase (should return false - update)
@zset.add('member1', 200, gt: true)
#=> false

## Return value: Add with GT for score decrease (should return false - no change)
@zset.add('member1', 150, gt: true)
#=> false

## Return value: Add with LT for new element (should return true)
@zset.clear
@zset.add('member1', 100, lt: true)
#=> true

## Return value: Add with LT for score decrease (should return false - update)
@zset.add('member1', 50, lt: true)
#=> false

## Return value: Add with LT for score increase (should return false - no change)
@zset.add('member1', 75, lt: true)
#=> false

## Return value: Add with XX+GT+CH for valid update (should return true)
@zset.clear
@zset.add('member1', 100)
@zset.add('member1', 200, xx: true, gt: true, ch: true)
#=> true

## Return value: Add with XX+GT+CH for invalid update (should return false)
@zset.add('member1', 150, xx: true, gt: true, ch: true)
#=> false

## Return value: All return values are Boolean type (not Integer)
@zset.clear
results = []
results << @zset.add('member1', 100)              # new
results << @zset.add('member1', 200)              # update
results << @zset.add('member2', 100, nx: true)    # new with NX
results << @zset.add('member2', 200, nx: true)    # existing with NX
results << @zset.add('member3', 100, xx: true)    # non-existing with XX
results << @zset.add('member1', 300, ch: true)    # update with CH
results.all? { |r| r.is_a?(TrueClass) || r.is_a?(FalseClass) }
#=> true
