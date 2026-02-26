# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing

**Tryouts framework rules:**
1. **Structure**: Each file has 3 sections - setup (optional), testcases, teardown (optional); each testcase has 3 required parts: description, code, expectations.
2. **Test cases**: Use `##` line prefix for test descriptions, Ruby code, then `#=>` expectations
3. **Variables**: Instance variables (`@var`) persist across sections; local variables do not.
4. **Expectations**: Multiple expectation types available (`#=>`, `#==>`, `#=:>`, `#=!>`, etc.); each testcase can have multiple expectations.
5. **Comments**: Use single `#` prefix, but DO NOT label file sections
6. **Philosophy**: Plain realistic code, avoid mocks/test DSL
7. **Result**: Last expression in each test case is the result

**Running tests:**
- **Basic**: `bundle exec try` (auto-discovers `*_try.rb` and `*.try.rb` files)
- **All options**: `bundle exec try --help` (complete CLI reference with agent-specific notes)

**Agent-optimized workflow:**
- **Default agent mode**: `bundle exec try --agent` (structured, token-efficient output for LLMs)
- **Focus modes**: `bundle exec try --agent --agent-focus summary` (options: `summary|first-failure|critical`)
  - `summary`: Overview of test results only
  - `first-failure`: Stop at first failure with details
  - `critical`: Only show critical issues and summary

**Framework integration:**
- **RSpec**: `bundle exec try --rspec` (generates RSpec-compatible output)
- **Minitest**: `bundle exec try --minitest` (generates Minitest-compatible output)

**Debugging options:**
- **Stack traces**: `bundle exec try -s` (stack traces without debug logging)
- **Verbose failures**: `bundle exec try -vfs` (detailed failure output)
- **Debug mode**: `bundle exec try -D` (additional logging including stack traces)
- **Shared context**: `bundle exec try --shared-context` (DEFAULT - reuse shared context across setup, testcases, and teardown)
- **Fresh context**: `bundle exec try --no-shared-context` (isolate test cases, no shared variables)

*Note: Use `--agent` mode for optimal token efficiency when analyzing test results programmatically.*


### Development Setup
- **Install dependencies**: `bundle install`
- **Generate documentation**: `bundle exec yard`
- **Code linting**: `bundle exec rubocop`

### Changelog Management

Add changelog fragment with each user-facing or documented change (optional but encouraged). Fragments use RST format. See:
@changelog.d/README.md

### Known Issues & Quirks
- **Reserved Keywords**: Cannot use `ttl`, `db`, `valkey`, `redis` as field names - use prefixed alternatives
- **Empty Identifiers**: Cause stack overflow in key generation - validate before operations
- **Lazy Initialization Races**: Connection chains and field collections use lazy initialization without synchronization (generally safe due to Ruby GIL, but not guaranteed)

### Debugging
- **Database command logging**: You can request real-time Database command monitoring from the user
  - Shows all Database operations with timestamps, database numbers, and full commands
  - Updates live as tests run or code executes
  - Essential for debugging Familia ORM Database interactions, multi/exec, pipelining, logical_database issues

## Architecture Overview

### Core Components

**Familia**: A Valkey-compatible ORM library that provides Ruby object storage with advanced features like expiration, safe dumping, and quantization.

#### Primary Classes
1. **`Familia::Horreum`** - Base class for Valkey-backed objects (like ActiveRecord models)
   - Located in `lib/familia/horreum.rb`
   - Provides field definitions, data type relationships, and object lifecycle management
   - Supports multiple identifier strategies: symbols, procs, arrays

2. **`Familia::DataType`** - Base class for Valkey data type wrappers
   - Located in `lib/familia/data_type.rb`
   - Provides String, JsonStringKey, List, UnsortedSet, SortedSet, HashKey implementations
   - Each type has its own class in `lib/familia/data_type/types/`

3. **`Familia::Base`** - Common module for both Horreum and DataType
   - Located in `lib/familia/base.rb`
   - Provides shared functionality and feature system

#### Feature System
Familia uses a modular feature system where features are mixed into classes:
- **Expiration** (`lib/familia/features/expiration.rb`) - TTL management with cascading
- **SafeDump** (`lib/familia/features/safe_dump.rb`) - API-safe object serialization
- **Relationships** (`lib/familia/features/relationships.rb`) - CRUD operations for related objects

#### Key Architectural Patterns

**Inheritance Chain**: `MyClass < Familia::Horreum` automatically extends `ClassMethods` and `Features`

**Common Pitfall: Overriding initialize**

⚠️ **Do NOT override `initialize` without calling `super`** - this breaks related field initialization.

**Bad - will cause crashes:**
```ruby
class User < Familia::Horreum
  def initialize(email)
    @email = email  # Missing super! Related fields won't work
  end
end
```

**Good - use the `init` hook to apply defaults (use `||=` not `=`):**
```ruby
class User < Familia::Horreum
  field :objid
  field :email

  # Called after Horreum sets fields from kwargs
  # IMPORTANT: Use ||= to apply defaults, not = to override
  def init
    @objid ||= SecureRandom.uuid  # Apply default only if not already set
    _run_post_init_hooks          # Additional setup logic
  end
end

# This works correctly:
user = User.new(email: 'test@example.com')
user.objid      # → generated UUID (applied by init)
user.email      # → 'test@example.com' (set by Horreum from kwargs)
```

**Okay - if absolutely necessary, override and call super explicitly:**
```ruby
class User < Familia::Horreum
  def initialize(email = nil, **kwargs)
    super # Initializes related fields here and also calls init
    @email ||= generate_email if email.nil?
  end
end
```

**Why this matters**: Familia's `initialize` method processes kwargs FIRST (setting fields), then calls `initialize_relatives` (setting up DataType objects), then calls your `init` hook. By the time `init` runs, kwargs have already been consumed and fields are set.

**The ||= Pattern Explained**:
```ruby
# WRONG - overwrites what Horreum already set
def init
  @email = generate_email  # Overwrites the correct value
end

# RIGHT - applies default only if not already set
def init
  @email ||= email               # Preserves value Horreum set from kwargs
  @email ||= 'default@example.com'  # Apply fallback default if still nil
end
```

**When to use each approach:**
- **Use `init` hook with `||=`** (preferred): Apply defaults, run validations, setup callbacks - any logic that should run after field initialization. Follows standard ORM lifecycle hook patterns.
- **Use explicit `super`**: Only when you need to intercept or transform arguments before Horreum processes them (rare).

**DataType Definition**: Use class methods to define keystore database-backed attributes:
```ruby
class User < Familia::Horreum
  field :email        # Simple field
  list :sessions      # Valkey/Redis list
  set :tags           # Valkey/Redis set
  zset :metrics       # Valkey/Redis sorted set
  hashkey :settings   # Valkey/Redis hash
end
```

**Identifier Resolution**: Multiple strategies for object identification:
- Symbol: `identifier_field :email`
- Proc: `identifier ->(user) { "user:#{user.email}" }`
- Array: `identifier [:type, :email]`

### Database Connection Management
- Connection handling in `lib/familia/connection.rb`
- Settings management in `lib/familia/settings.rb`
- Database selection via `logical_database` class method
- URI-based configuration support

### Important Implementation Notes

**Field Initialization**: Objects can be initialized with positional args (brittle) or keyword args (robust). Keyword args are recommended. All non-nil values including `false` and `0` are preserved during initialization.

**Serialization**: All field values are JSON-encoded for storage and JSON-decoded on retrieval to preserve Ruby types (Integer, Boolean, String, Float, Hash, Array, nil). This ensures type preservation across the Redis storage boundary. For example:
- `age: 35` (Integer) stores as `"35"` in Redis and loads back as Integer `35`
- `active: true` (Boolean) stores as `"true"` in Redis and loads back as Boolean `true`
- `metadata: {key: "value"}` (Hash) stores as JSON and loads back as Hash with proper types

**Serialization by Type** (what you see in `redis-cli HGETALL` or `GET`):

| Context | Serialize method | Ruby `"UK"` in Redis | Ruby `123` in Redis | Deserialize method |
|---|---|---|---|---|
| Horreum `field` | `serialize_value` (JSON) | `"\"UK\""` | `"123"` | `deserialize_value` (JSON parse) |
| `StringKey` | `.to_s` (raw) | `"UK"` | `"123"` | raw string (no parse) |
| `JsonStringKey` | JSON dump | `"\"UK\""` | `"123"` | JSON parse |
| `List/Set/SortedSet/HashKey` values | `serialize_value` (JSON) | `"\"UK\""` | `"123"` | `deserialize_value` (JSON parse) |

Key distinction: `StringKey` uses raw `.to_s` serialization (not JSON) to support Redis string operations like `INCR`, `DECR`, and `APPEND`. All other types use JSON encoding. When inspecting raw Redis output, a Horreum string field storing `"UK"` appears as `"\"UK\""` (double-quoted), while a `StringKey` storing `"UK"` appears as `"UK"` (no extra quotes).

Use `debug_fields` on a Horreum instance to see Ruby values vs stored JSON side-by-side:
```ruby
user.debug_fields
# => {"country" => {ruby: "UK", stored: "\"UK\"", type: "String"},
#     "age"     => {ruby: 30,   stored: "30",      type: "Integer"}}
```

**Database Key Generation**: Automatic key generation using class name, identifier, and field/type names (aka dbkey). Pattern: `classname:identifier:fieldname`

**Memory Efficiency**: Only non-nil values are stored in keystore database to optimize memory usage.

**Thread Safety**: Data types are frozen after instantiation to ensure immutability.

### Write Model: Deferred vs Immediate

Familia has a two-tier write model. Understanding when data hits Redis is critical for avoiding inconsistencies.

**Scalar fields** (defined with `field`) use deferred writes:
- Normal setters (`user.name = "Alice"`) only update the in-memory instance variable. Nothing is written to Redis until `save`, `commit_fields`, or `batch_update` is called.
- Fast writers (`user.name! "Alice"`) perform an immediate `HSET` on the object's hash key. Use these when you need a single field persisted without a full save cycle.

**Collection fields** (defined with `list`, `set`, `zset`, `hashkey`) use immediate writes:
- Every mutating method (`add`, `push`, `remove`, `clear`, `[]=`) executes the corresponding Redis command (SADD, RPUSH, ZREM, DEL, etc.) right away.
- Collection fields live on separate Redis keys from the object's hash, so they cannot participate in the same MULTI/EXEC transaction as scalar fields.

**Safe pattern -- scalars first, then collections:**
```ruby
plan.name = "Premium"
plan.region = "US"
plan.save  # HMSET for all scalar fields

# Collections mutated AFTER scalars are committed
plan.features.clear
plan.features.add("sso")
plan.features.add("priority_support")

# Or use the convenience wrapper:
plan.save_with_collections do
  plan.features.clear
  plan.features.add("sso")
end
```

**Unsafe pattern -- collections before save:**
```ruby
plan.name = "Premium"
plan.features.clear           # Immediate: Redis DEL
plan.features.add("sso")     # Immediate: Redis SADD
plan.save                     # If this raises, features are already mutated
```

**Cross-database limitation**: MULTI/EXEC transactions only work within a single Redis database number. If scalar fields and a collection use different `logical_database` values, they cannot share a transaction. The `save_with_collections` pattern handles this by sequencing the operations rather than wrapping them in MULTI.

**Instances timeline**: The class-level `instances` sorted set is a timeline of last-modified times, not a registry. `persist_to_storage` (called by `save`) and `commit_fields`/`batch_update` all call `touch_instances!` to update the timestamp. Use `in_instances?(identifier)` for fast O(log N) checks without loading the object.

### Instances Timeline Lifecycle

Every Horreum subclass has a class-level `instances` sorted set (a `class_sorted_set` with `reference: true`). This timeline maps identifiers to their last-write timestamp (ZADD score).

**Write paths that touch instances** (call `touch_instances!`):
- `save` / `save_if_not_exists!` (via `persist_to_storage`)
- `commit_fields`
- `batch_update`
- `save_fields`
- Fast writers (`field_name!`) via `FieldType` and `DefinitionMethods`

**Write paths that remove from instances**:
- Instance-level `destroy!` (via `remove_from_instances!`)
- Class-level `destroy!(identifier)` (direct `instances.remove`)
- `cleanup_stale_instance_entry` in `find_by_dbkey` (lazy, on-access pruning)

**Ghost objects**: When a hash key expires via TTL but the identifier still lingers in `instances`, enumerating `instances.to_a` returns identifiers for objects that no longer exist. These are cleaned lazily: `find_by_dbkey` detects the missing key and calls `cleanup_stale_instance_entry`. Code that enumerates without loading (e.g. `instances.members`) will still see ghosts.

**`in_instances?` vs `exists?`**:
- `in_instances?(id)` checks the `instances` sorted set -- fast O(log N), but may return true for expired keys (ghost entries) or false for objects created outside Familia
- `exists?(id)` checks the actual Redis hash key -- authoritative but requires a round-trip

**`load` / `find_by_id` bypasses instances**: These methods read directly from the hash key via HGETALL. They do not consult `instances`. A key can exist in Redis without being in instances (e.g. created by `commit_fields` in an older version), and vice versa.

## Thread Safety Considerations

### Current Thread Safety Status (as of 2025-10-21)

Familia has **good thread safety** for standard multi-threaded environments:

### Testing Thread Safety

Thread safety tests are available in `try/thread_safety/`:
- **100% passing** (56/56 tests)
- **CyclicBarrier pattern** for maximum contention testing
- **Test execution**: ~300ms for full suite with 1,000+ concurrent operations
- **Production monitoring**: 10/10 monitoring tests passing

Run thread safety tests:
```bash
bundle exec try --agent try/thread_safety/
bundle exec try --agent try/unit/thread_safety_monitor_try.rb
```

### Best Practices for Thread-Safe Usage

1. **Configure Once at Startup**: Module-level configuration should be set before threads spawn
2. **Use Immutable DataTypes**: Leverage the fact that DataType instances are frozen
3. **Test Under Concurrency**: Use the patterns in `try/thread_safety/` to verify thread safety
4. **Enable Production Monitoring**: Use `Familia.start_monitoring!` to track contention in production
