# Optimized Loading Guide

> **💡 Quick Reference**
>
> Reduce Redis commands by 50-96% for bulk object loading:
> ```ruby
> # Single object (50% reduction)
> user = User.find_by_id(123, check_exists: false)
>
> # Bulk loading (96% reduction)
> users = User.load_multi([123, 456, 789])
> ```

## Overview

Familia's optimized loading provides two complementary strategies to dramatically reduce Redis command overhead when loading objects. These optimizations are particularly valuable for applications loading collections of related objects, processing query results, or operating in high-throughput environments.

**Default behavior**: Each object load requires 2 Redis commands (EXISTS + HGETALL)

**Optimized approaches**:
1. **Skip EXISTS check** (`check_exists: false`) - 50% reduction, 1 command per object
2. **Pipelined bulk loading** (`load_multi`) - Up to 96% reduction, 1 round trip for N objects

## Why Optimize Object Loading?

**Network Overhead**: Each Redis command incurs network round-trip latency. For 14 objects, default loading requires 28 round trips.

**Bulk Operations**: Loading collections of related objects (e.g., metadata for a customer, domains for a team) compounds the overhead.

**High Throughput**: APIs serving thousands of requests per second benefit significantly from reduced Redis commands.

**Cost Efficiency**: Fewer commands mean lower Redis server load and reduced infrastructure costs in cloud environments.

## The Problem

Consider loading metadata objects for a customer:

```ruby
# Get metadata IDs from sorted set
metadata_ids = customer.metadata.rangebyscore(start_time, end_time)
# => ["id1", "id2", "id3", ..., "id14"]  # 14 metadata objects

# Traditional approach
metadata = metadata_ids.map { |id| Metadata.find_by_id(id) }
```

**Redis commands generated**:
```
exists metadata:id1:object     # Check 1
hgetall metadata:id1:object    # Load 1
exists metadata:id2:object     # Check 2
hgetall metadata:id2:object    # Load 2
... (repeated 14 times)
# Total: 28 commands across 28 network round trips
```

## Quick Start

### Optimization 1: Skip EXISTS Check

For single object loads or when iterating over collections:

```ruby
# Default behavior (2 commands)
user = User.find_by_id(123)

# Optimized (1 command)
user = User.find_by_id(123, check_exists: false)

# Still returns nil for non-existent objects
missing = User.find_by_id(999, check_exists: false)  # => nil
```

**When to use**:
- Loading objects from known-to-exist references (sorted set members, etc.)
- Performance-critical paths where 50% reduction matters
- Iterating over collections with `.map`

**Performance**: 14 objects → 14 commands instead of 28 (50% reduction)

### Optimization 2: Pipelined Bulk Loading

For loading multiple objects at once:

```ruby
# Optimized bulk loading (1 round trip)
users = User.load_multi([123, 456, 789])

# With metadata example from above
metadata = Metadata.load_multi(metadata_ids)

# Filter out nils for missing objects
existing_metadata = Metadata.load_multi(metadata_ids).compact
```

**When to use**:
- Loading collections of related objects
- Processing query results (ZRANGEBYSCORE, SMEMBERS, etc.)
- Batch operations
- Any scenario requiring multiple object lookups

**Performance**: 14 objects → 1 pipelined batch with 14 HGETALL commands (96% reduction in round trips)

## Detailed Usage

### check_exists Parameter

The `check_exists` parameter is available on all finder methods:

```ruby
# find_by_dbkey
user = User.find_by_dbkey("user:123:object", check_exists: false)

# find_by_identifier
user = User.find_by_identifier(123, check_exists: false)

# Aliases (find_by_id, find, load)
user = User.find_by_id(123, check_exists: false)
user = User.find(123, check_exists: false)
user = User.load(123, check_exists: false)

# Custom suffix
session = Session.find_by_identifier('abc123', :session, check_exists: false)
```

**How it works**:

**Safe mode** (`check_exists: true`, default):
1. Send `EXISTS user:123:object`
2. If key doesn't exist, return nil immediately
3. If exists, send `HGETALL user:123:object`
4. Instantiate object from hash

**Optimized mode** (`check_exists: false`):
1. Send `HGETALL user:123:object` directly
2. If hash is empty (key doesn't exist), return nil
3. Otherwise instantiate object from hash

**Safety**: Both modes return nil for non-existent keys. Optimized mode detects non-existence via empty hash response.

### Pipelined Bulk Loading

#### load_multi

Load multiple objects by their identifiers:

```ruby
# Basic usage
users = User.load_multi([123, 456, 789])

# Returns array with nils for missing objects
results = User.load_multi(['id1', 'missing', 'id3'])
# => [<User:id1>, nil, <User:id3>]

# Filter out nils
existing = User.load_multi(ids).compact

# Empty array handling
User.load_multi([])  # => []

# Preserves order
users = User.load_multi([789, 123, 456])
users.map(&:user_id)  # => [789, 123, 456] (same order)
```

**Parameters**:
- `identifiers` - Array of identifiers (Strings or Integers)
- `suffix` - Optional suffix (default: class suffix)

**Returns**: Array of objects in same order as input, with nils for non-existent keys

#### load_multi_by_keys

Load objects by full dbkeys (lower-level variant):

```ruby
# When you already have full keys
keys = [
  "user:123:object",
  "user:456:object",
  "user:789:object"
]
users = User.load_multi_by_keys(keys)

# Mixed existing and non-existent keys
keys = ["user:123:object", "user:missing:object"]
results = User.load_multi_by_keys(keys)
# => [<User:123>, nil]
```

**When to use**: When working directly with dbkeys rather than identifiers (rare).

#### load_batch Alias

`load_batch` is an alias for `load_multi`:

```ruby
users = User.load_batch([123, 456, 789])
# Identical to load_multi
```

### Handling Edge Cases

```ruby
# Nil identifiers
results = User.load_multi(['id1', nil, 'id3'])
# => [<User:id1>, nil, <User:id3>]

# Empty string identifiers
results = User.load_multi(['id1', '', 'id3'])
# => [<User:id1>, nil, <User:id3>]

# All missing
results = User.load_multi(['missing1', 'missing2'])
results.compact  # => []

# Mixed with compact
existing = User.load_multi(ids).compact
# Only non-nil objects
```

## Performance Comparison

### Single Object Loading

| Method | Commands | Round Trips | Use Case |
|--------|----------|-------------|----------|
| `find_by_id(id)` (default) | 2 | 2 | Safe, defensive code |
| `find_by_id(id, check_exists: false)` | 1 | 1 | Performance-critical |
| `load_multi([id])` | 1 | 1 | Bulk API consistency |

### Bulk Loading (14 Objects)

| Method | Commands | Round Trips | Improvement |
|--------|----------|-------------|-------------|
| `ids.map { \|id\| find(id) }` | 28 | 28 | Baseline |
| `ids.map { \|id\| find(id, check_exists: false) }` | 14 | 14 | 50% reduction |
| `load_multi(ids)` | 14 | 1 | 96% reduction |

### Real-World Example

Loading customer metadata (your use case):

```ruby
# Get metadata IDs from sorted set (1 command)
metadata_ids = customer.metadata.rangebyscore(start_time, end_time)
# => 14 metadata IDs

# ❌ Traditional approach: 28 commands, 28 round trips
metadata = metadata_ids.map { |id| Metadata.find_by_id(id) }

# ✅ Optimized approach: 14 commands, 14 round trips (50% reduction)
metadata = metadata_ids.map { |id| Metadata.find_by_id(id, check_exists: false) }

# ✅✅ Best approach: 14 commands, 1 round trip (96% reduction)
metadata = Metadata.load_multi(metadata_ids).compact

# Total commands for full operation:
# Traditional: 1 (ZRANGEBYSCORE) + 28 (loading) = 29 commands
# Optimized: 1 (ZRANGEBYSCORE) + 1 (pipelined batch) = 2 commands
# Improvement: 93% reduction
```

## Best Practices

### 1. Use load_multi for Bulk Operations

**Always prefer** `load_multi` when loading multiple objects:

```ruby
# ❌ Avoid
domain_ids = team.domains.members
domains = domain_ids.map { |id| Domain.find_by_id(id) }

# ✅ Better
domain_ids = team.domains.members
domains = Domain.load_multi(domain_ids).compact
```

### 2. Use check_exists: false for Trusted References

When loading objects from known-to-exist references:

```ruby
# Objects from sorted set members
participant_ids = event.participants.members
participants = participant_ids.map { |id|
  User.find_by_id(id, check_exists: false)
}

# Even better with load_multi
participants = User.load_multi(participant_ids).compact
```

### 3. Keep Default Behavior for Defensive Code

Use default `check_exists: true` when:
- Loading from user input
- Defensive/paranoid code paths
- Single object lookups where optimization doesn't matter
- Initial development before optimization phase

```ruby
# User input - keep safe mode
user = User.find_by_id(params[:user_id])

# Internal lookup - optimize
user = User.find_by_id(session.user_id, check_exists: false)
```

### 4. Compact Results Appropriately

Handle nils based on your requirements:

```ruby
# When all objects should exist (raise on missing)
users = User.load_multi(ids)
if users.any?(&:nil?)
  raise "Missing users: #{ids.zip(users).select { |_, u| u.nil? }}"
end

# When missing objects are acceptable
existing_users = User.load_multi(ids).compact

# When you need to track which are missing
results = ids.zip(User.load_multi(ids))
results.each do |id, user|
  if user.nil?
    logger.warn "User #{id} not found"
  else
    process_user(user)
  end
end
```

### 5. Measure Before Optimizing

Profile your application to identify bottlenecks:

```ruby
# Add timing to measure impact
require 'benchmark'

ids = (1..100).to_a

# Traditional
traditional_time = Benchmark.realtime do
  users = ids.map { |id| User.find_by_id(id) }
end

# Optimized
optimized_time = Benchmark.realtime do
  users = User.load_multi(ids)
end

puts "Traditional: #{traditional_time}s"
puts "Optimized: #{optimized_time}s"
puts "Speedup: #{(traditional_time / optimized_time).round(1)}x"
```

## Implementation Details

### Empty Hash Detection

When `check_exists: false`, non-existent keys are detected via empty hash:

```ruby
# Non-existent key
hash = redis.hgetall("user:missing:object")
# => {}  # Empty hash indicates key doesn't exist

# Existing key with no fields (edge case)
redis.hset("user:empty:object", "placeholder", "")
redis.hdel("user:empty:object", "placeholder")
hash = redis.hgetall("user:empty:object")
# => {}  # Also empty, but key technically exists

# Both cases safely return nil
```

**Note**: In practice, Familia objects always have fields, so empty hashes reliably indicate non-existent keys.

### Pipelining vs Individual Commands

**Individual commands**:
```ruby
# Each command is a separate round trip
ids.each do |id|
  key = "user:#{id}:object"
  redis.hgetall(key)  # Round trip 1, 2, 3, ...
end
```

**Pipelined commands**:
```ruby
# All commands in single round trip
redis.pipelined do |pipeline|
  ids.each do |id|
    key = "user:#{id}:object"
    pipeline.hgetall(key)  # Queued locally
  end
end  # Single round trip with all commands
```

### Field Deserialization

All optimized methods use the same deserialization logic as standard loading:

```ruby
# All field types are properly handled
user = User.load_multi([123]).first
user.age        # Integer field correctly deserialized
user.active     # Boolean field correctly deserialized
user.metadata   # Hash field correctly deserialized
user.tags       # Array field correctly deserialized
```

**Technical details**:
- Uses `initialize_with_keyword_args_deserialize_value` internally
- JSON deserialization for all field values
- Proper type preservation (Integer, Boolean, Hash, Array, nil)

## Migration Guide

### Identifying Optimization Opportunities

Look for these patterns in your codebase:

```ruby
# Pattern 1: Mapping over collection of IDs
ids.map { |id| Model.find_by_id(id) }
ids.map { |id| Model.find(id) }
ids.map { |id| Model.load(id) }

# Pattern 2: Loading from sorted set members
member_ids = sorted_set.members
members = member_ids.map { |id| Model.find(id) }

# Pattern 3: Loading from set members
tag_ids = set.members
tags = tag_ids.map { |id| Tag.find(id) }

# Pattern 4: Processing query results
user_ids = redis.zrangebyscore("users:active", start_score, end_score)
users = user_ids.map { |id| User.find(id) }
```

### Step-by-Step Migration

**Step 1**: Identify bulk loading patterns
```bash
# Search your codebase
grep -r "\.map.*find_by_id" app/
grep -r "\.map.*\.find(" app/
```

**Step 2**: Replace with `load_multi`
```ruby
# Before
domains = domain_ids.map { |id| Domain.find(id) }

# After
domains = Domain.load_multi(domain_ids).compact
```

**Step 3**: Profile the change
```ruby
# Add logging temporarily
start = Familia.now
domains = Domain.load_multi(domain_ids).compact
duration = Familia.now - start
Rails.logger.info "Loaded #{domains.size} domains in #{duration}s"
```

**Step 4**: Deploy and monitor
- Check error rates remain stable
- Monitor Redis command counts
- Verify response times improve

### Backwards Compatibility

All changes are fully backwards compatible:

```ruby
# Existing code continues to work
user = User.find_by_id(123)  # Still works, still safe

# New optional parameter
user = User.find_by_id(123, check_exists: false)  # Opt-in optimization

# New methods
users = User.load_multi(ids)  # New method, doesn't break existing code
```

## Common Patterns

### Pattern 1: Loading Related Objects

```ruby
class Team < Familia::Horreum
  identifier_field :team_id
  field :team_id, :name
  sorted_set :member_ids  # Stores user IDs with scores
end

# Efficient member loading
def load_team_members(team)
  member_ids = team.member_ids.members
  User.load_multi(member_ids).compact
end

# With sorting by score
def load_recent_members(team, limit: 10)
  member_ids = team.member_ids.revrange(0, limit - 1)
  User.load_multi(member_ids).compact
end
```

### Pattern 2: Filtered Loading

```ruby
# Load and filter in one pass
def load_active_users(user_ids)
  User.load_multi(user_ids).compact.select(&:active?)
end

# Load with transformation
def load_user_emails(user_ids)
  User.load_multi(user_ids).compact.map(&:email)
end

# Load with stats
def load_with_stats(user_ids)
  users = User.load_multi(user_ids)
  {
    found: users.compact.size,
    missing: users.count(&:nil?),
    users: users.compact
  }
end
```

### Pattern 3: Batch Processing

```ruby
# Process in batches to avoid memory issues
def process_all_users(batch_size: 100)
  user_ids = User.instances.members  # Get all user IDs

  user_ids.each_slice(batch_size) do |batch_ids|
    users = User.load_multi(batch_ids).compact

    users.each do |user|
      process_user(user)
    end
  end
end
```

### Pattern 4: Multi-Model Loading

```ruby
# Load related objects across different models
def load_dashboard_data(user_id)
  user = User.find_by_id(user_id, check_exists: false)

  # Load user's teams and domains in parallel
  team_ids = user.team_ids.members
  domain_ids = user.domain_ids.members

  teams = Team.load_multi(team_ids).compact
  domains = Domain.load_multi(domain_ids).compact

  {
    user: user,
    teams: teams,
    domains: domains
  }
end
```

## Troubleshooting

### Issue: Unexpected nils in Results

**Problem**: `load_multi` returns more nils than expected

**Causes**:
1. Objects genuinely don't exist
2. Wrong identifier field being used
3. Suffix mismatch

**Solution**:
```ruby
# Debug which objects are missing
ids = [1, 2, 3]
results = User.load_multi(ids)
missing_ids = ids.zip(results).select { |_, obj| obj.nil? }.map(&:first)
puts "Missing: #{missing_ids}"

# Check if keys exist
missing_ids.each do |id|
  key = User.dbkey(id)
  exists = Familia.redis.exists(key)
  puts "#{key}: #{exists}"
end

# Verify correct suffix
User.suffix  # Check what suffix the class uses
```

### Issue: Performance Not Improving

**Problem**: `load_multi` doesn't seem faster

**Causes**:
1. Small dataset (overhead of pipelining)
2. Local Redis instance (network latency minimal)
3. Not actually using `load_multi`

**Solution**:
```ruby
# Benchmark with realistic dataset
require 'benchmark'

# Create test data
ids = (1..100).map do |i|
  user = User.new(user_id: i, name: "User #{i}")
  user.save
  i
end

# Compare approaches
Benchmark.bm(20) do |x|
  x.report("traditional:") { ids.map { |id| User.find(id) } }
  x.report("check_exists:false:") { ids.map { |id| User.find(id, check_exists: false) } }
  x.report("load_multi:") { User.load_multi(ids) }
end
```

### Issue: Order Not Preserved

**Problem**: Results appear in wrong order

**Cause**: Using `compact` changes indices

**Solution**:
```ruby
# ❌ Loses position information
ids = [1, 2, 3]
users = User.load_multi(ids).compact  # [<User:1>, <User:3>] if 2 is missing

# ✅ Preserve positions with zip
ids.zip(User.load_multi(ids)).each do |id, user|
  if user
    puts "Processing user #{id}"
    process_user(user)
  else
    puts "User #{id} not found"
  end
end

# ✅ Or track original indices
users_with_ids = User.load_multi(ids).map.with_index do |user, idx|
  [ids[idx], user]
end
```

## See Also

- [Core Field System](core-field-system.md) - Understanding Familia's field types
- [Relationships Guide](feature-relationships.md) - Loading related objects
- [Time Utilities](time-utilities.md) - For score-based queries with timestamps
- [Implementation Guide](implementation.md) - Advanced Familia internals
