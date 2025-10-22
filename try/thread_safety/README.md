# Thread Safety Test Suite

## Purpose

This directory contains targeted tests that expose threading vulnerabilities in Familia's codebase. These tests were created following a systematic analysis that identified critical race conditions in production code that currently have no synchronization protection.

**Key Insight**: These tests are designed to **fail or expose inconsistencies** because the underlying code lacks proper synchronization. As of the latest updates, test assertions have been strengthened to properly verify thread safety invariants (singleton properties, consistency, etc.) rather than just checking thread completion.

**Current Status**: As of 2025-10-21, test suite has **61 passing / 4 failing** tests. The 4 failures properly detect real race conditions and bugs that need fixing in production code. This honest failure rate is intentional and expected - it shows exactly where work is needed.

## The Thread Safety Problem

Familia uses several patterns that are inherently unsafe under concurrent access:

### 1. Lazy Initialization Without Synchronization
```ruby
# This pattern appears throughout the codebase
def connection_chain
  @connection_chain ||= build_connection_chain  # RACE CONDITION
end
```

**The Race**: Two threads can both see `@connection_chain` as nil, both call `build_connection_chain`, and create duplicate objects. The second write wins, but the first object is leaked.

**Where it appears**:
- Module-level connection chain
- Class-level connection chain (per Horreum subclass)
- Feature registry collections
- Field definition collections
- Various caches (encryption manager, SecureIdentifier, logger)

### 2. Check-Then-Act Races
```ruby
# From middleware registration
if !@logger_registered
  RedisClient.register(DatabaseLogger)  # RACE CONDITION
  @logger_registered = true
end
```

**The Race**: Thread A checks the flag (false), gets interrupted. Thread B checks (false), registers middleware, sets flag. Thread A resumes and registers again - now you have duplicate middleware in the chain.

### 3. Non-Atomic Updates
```ruby
# From middleware versioning
def increment_middleware_version!
  @middleware_version += 1  # RACE CONDITION: read-modify-write
end
```

**The Race**: Classic lost update problem. With 100 concurrent increments, you might get 97 instead of 100 due to interleaved reads.

### 4. Unprotected Shared State
```ruby
# Module configuration
@uri = URI.parse('redis://...')
@prefix = nil
@delim = ':'
# Multiple threads can read/write these without coordination
```

**The Race**: Thread A reads `@delim` as ":", Thread B changes it to "::", Thread A uses the old value - inconsistent key generation.

## Testing Strategy

### What We're Testing For

1. **Singleton Violations**: Lazy initialization creating multiple instances
2. **Lost Updates**: Concurrent increments not all counted
3. **State Inconsistency**: Reads getting partially-updated values
4. **Duplicate Operations**: Check-then-act races causing double-execution
5. **Isolation Failures**: Fiber-local storage leaking between fibers

### How We Test

#### CyclicBarrier for Maximum Contention
We deliberately synchronize thread start to maximize the chance of exposing races:

```ruby
barrier = Concurrent::CyclicBarrier.new(50)
threads = 50.times.map do
  Thread.new do
    barrier.wait  # All 50 threads pause here
    # Now they all execute the racy code simultaneously
    @connection_chain ||= build_connection_chain
  end
end
```

This isn't "production realistic" - it's **deliberately adversarial** to expose bugs that might only happen 1 in 1000 times in production.

#### Concurrent::Array for Safe Result Collection
Standard Ruby arrays aren't thread-safe. We use `Concurrent::Array` to collect results without adding our own bugs:

```ruby
results = Concurrent::Array.new  # Thread-safe
threads.each { |t| results << t.value }
```

#### Multi-Property Assertion Pattern
Test multiple invariants together to catch different types of corruption:

```ruby
# Test array corruption, correctness, and completeness
[results.any?(nil), results.all? { |r| r == 'PONG' }, results.size]
#=> [false, true, 50]
```

This pattern catches:
- **Array corruption**: `results.any?(nil)` detects concurrent modification bugs
- **Correctness**: `results.all? { ... }` verifies logical correctness
- **Completeness**: `results.size` ensures no lost operations

#### CountDownLatch for Timeout Protection
Tests should never hang forever if there's a deadlock:

```ruby
latch = Concurrent::CountDownLatch.new(10)
# ... spawn threads ...
latch.wait(5)  # Fail fast if deadlock occurs
```

### What Success Looks Like

**Before Fix** (current state):
```ruby
## Concurrent connection chain initialization
# ...50 threads all call Familia.dbclient...
results.uniq.size
#=> 3  # FAIL: Created 3 different chains (race condition)
```

**After Fix** (with Mutex):
```ruby
## Concurrent connection chain initialization
# ...50 threads all call Familia.dbclient...
results.uniq.size
#=> 1  # PASS: Only one chain created (thread-safe)
```

## Recent Changes (2025-10-21)

**Test Assertion Improvements**: Test assertions have been updated to properly verify thread safety rather than just checking thread completion. For example:

**Before** (weak assertion):
```ruby
chains << chain.class.name
threads.each(&:join)
chains.size  # Only checks 50 threads completed
#=> 50
```

**After** (strong assertion):
```ruby
chains << chain.object_id  # Store actual object identity
threads.each(&:join)
chains.uniq.size  # Checks singleton property
#=> 1  # Will FAIL if race creates multiple chains
```

This makes tests properly fail when race conditions occur, providing honest feedback about thread safety status.

## Current Test Results

**Test Suite**: 63 total tests across 9 files
**Status**: 61 passing, 2 failing (736ms runtime)
**Coverage**: ~30% of identified thread safety risks (target: ~85%)

### Known Failures (Real Bugs Detected)

These 2 failures properly detect a real race condition in production code:

#### 1. Connection Chain Lazy Init (`connection_chain_race_try.rb:39`)

**Failure**: Expected `[false, 1]` but got `[false, 50]`
- Module-level `@connection_chain ||= build_connection_chain` lacks Mutex protection
- Creates 50 different chain instances under concurrent access (should be 1)
- **Root cause**: `lib/familia/connection.rb:95`
- **Fix needed**: Add Mutex synchronization around lazy initialization

#### 2. Connection Chain Rebuild (`connection_chain_race_try.rb:123`)

**Failure**: Expected `[false, true, 40]` but got `[false, false, 40]`
- One thread nils out `@connection_chain` while 39 others try to use it
- Some threads get errors instead of successful RedisClient instances
- **Root cause**: No synchronization protecting chain rebuilding
- **Fix needed**: Mutex around connection chain access

### Removed Tests (Investigation Revealed Not Bugs)

These tests were removed after thorough investigation revealed they were based on incorrect assumptions:

#### 3. Sample Rate Counter Test (REMOVED - NOT A BUG)

**Original Failure**: Expected `[true, false]` (sampled ~50%), got `[false, false]` (logged all 100)

**Investigation Result**:
- `sample_rate` controls **logging output**, not **command capture**
- The `commands` array always contains all commands regardless of sample_rate
- This is intentional behavior per `database_logger.rb:153-154`
- Comment states: "Command capture is unaffected - only logger output is sampled"
- **Status**: Removed from `middleware_thread_safety_try.rb:113`

#### 4. Pipeline Command Logging Test (REMOVED - NOT A BUG)

**Original Failure**: Expected 20 pipeline commands with ' | ', got only 16

**Investigation Result**:
- Single-command pipelines exist and are valid
- `Array#join(' | ')` only adds separators BETWEEN elements
- Single-command pipeline: `['SET key val']` → no separator (nothing to separate)
- Multi-command pipeline: `['SET key1 val1', 'SET key2 val2']` → has separator
- Backend-dev investigation created 7 diagnostic testcases confirming correct behavior
- See `try/investigation/pipeline_routing/CONCLUSION.md` for full technical analysis
- **Status**: Removed from `middleware_thread_safety_try.rb:224`

## Coverage Status

### Working Protection (2 areas)
- ✅ **DatabaseLogger**: Uses Mutex + Concurrent::Array
- ✅ **DatabaseCommandCounter**: Uses Concurrent::AtomicFixnum

These are good examples of proper synchronization.

### No Protection - HIGH RISK (6 areas)
- ❌ Middleware registration flags
- ❌ Middleware version counter
- ❌ Connection chain lazy init (module and class level)
- ❌ Field collections lazy init
- ❌ Module configuration state

### No Protection - MEDIUM RISK (6 areas)
- ⚠️ Various caches (encryption, SecureIdentifier, logger)
- ⚠️ Feature registry
- ⚠️ Class inheritance copying

### Fiber Isolation (needs verification)
- 🔍 Transaction fiber-local storage
- 🔍 Pipeline fiber-local storage

These *should* be safe by design (fiber-local variables), but we need tests to verify no leakage.

## Known Test Issues

Most tests need minor fixes before they can run properly:

### 1. Model Identifier Pattern
Tests currently use `identifier :object_id` which isn't valid Familia syntax.

**Need to use**:
```ruby
class TestModel < Familia::Horreum
  identifier_field :model_id
  field :model_id

  def init
    @model_id ||= SecureRandom.hex(8)
  end
end
```

### 2. Tryouts Expectation Format
Last line must be the value being tested, not a variable reference:

```ruby
# Wrong
results.size
#=> results.size == 20

# Right
results.size
#=> 20
```

### 3. Fiber Cross-Thread Issues
Fibers can't be resumed across thread boundaries. Tests need restructuring to create fibers within threads, not across them.

## How to Use These Tests

### Running Tests
```bash
# All thread safety tests
bundle exec try try/thread_safety/

# Single file
bundle exec try try/thread_safety/middleware_registration_race_try.rb

# With LLM-friendly output
FAMILIA_DEBUG=0 bundle exec try --agent try/thread_safety/
```

### Interpreting Results

**Test Passes**: The code has proper synchronization for this scenario.

**Test Fails with Inconsistent Results**: Race condition confirmed. Example:
```
expected 1, got 3  # Created 3 objects instead of 1 (singleton violation)
expected 100, got 97  # Lost 3 updates (non-atomic increment)
```

**Test Fails with Errors**: Usually means the test itself needs fixing (see Known Issues above), not necessarily a threading bug.

### Development Workflow

1. **Fix a test** to run properly (identifier, expectations, fiber issues)
2. **Run the test** - expect it to fail or show inconsistencies
3. **Add synchronization** to the production code (Mutex, AtomicFixnum, etc.)
4. **Run test again** - should now pass consistently
5. **Repeat** for next test

### When Adding New Code

Ask these questions:

1. **Is this shared mutable state?** → Needs synchronization
2. **Is this lazy initialization?** → Use Mutex or eager initialization
3. **Is this a counter?** → Use Concurrent::AtomicFixnum
4. **Is this check-then-act?** → Make atomic or use Mutex
5. **Is this a cache?** → Use ThreadSafe::Cache from concurrent-ruby

## Thread Counts Matter

- **10 threads**: Smoke test - catches obvious issues
- **20-50 threads**: Standard - catches most race conditions
- **100 threads**: Stress test - thorough but slower
- **1000+ threads**: Overkill - flaky, slow, not recommended

We use 20-100 threads in these tests as a sweet spot between detection and speed.

## Advanced Testing Patterns

These patterns are derived from the comprehensive middleware thread safety tests and can be applied to test any concurrent code.

### 1. Structure Validation Pattern
Verify that concurrent operations don't corrupt data structures:

```ruby
all_valid = results.all? do |item|
  item.field1.is_a?(String) &&
  item.field2.is_a?(Integer) &&
  item.field3.is_a?(Float)
end

[results.size, results.any?(nil), all_valid]
#=> [50, false, true]
```

### 2. Concurrent Clearing Pattern
Test that clearing operations don't corrupt during active usage:

```ruby
# 50 threads writing
writers = 50.times.map do
  Thread.new do
    barrier.wait
    10.times { write_operation }
  end
end

# 1 thread clearing
clearer = Thread.new do
  barrier.wait
  5.times { clear_operation }
end

# Array should never contain nil entries
results.any?(nil)
#=> false
```

### 3. Mixed Operation Types Pattern
Test different operations concurrently to expose interaction bugs:

```ruby
threads = 60.times.map do |i|
  Thread.new do
    barrier.wait
    case i % 3
    when 0  # Operation type A
      regular_operation
    when 1  # Operation type B
      pipeline_operation
    when 2  # Operation type C
      rapid_operations
    end
  end
end
```

### 4. Rapid Sequential Calls Pattern
Test that rapid-fire operations within threads don't corrupt state:

```ruby
threads = 20.times.map do
  Thread.new do
    # Each thread hammers the system
    10.times { operation }
  end
end

# Should have 200 results (20 × 10), all valid
[results.size, results.any?(nil)]
#=> [200, false]
```

### 5. Type and Method Validation Pattern
Ensure objects maintain their interface under concurrency:

```ruby
# All results should respond to expected methods
results.all? { |r| r.respond_to?(:expected_method) }
#=> true

# All results should be correct type
results.all? { |r| r.is_a?(ExpectedClass) }
#=> true
```

## Architecture Insights

### Why Familia Has These Issues

1. **Module-level state**: Familia uses module instance variables for global config
2. **Class-level state**: Each Horreum subclass has its own connection chain, field collections, etc.
3. **Lazy initialization**: Performance optimization that trades safety for speed
4. **No threading in original design**: Familia was designed for single-threaded use

### The Fiber Safety Assumption

Familia uses fiber-local storage for transactions and pipelines:
```ruby
Fiber[:familia_transaction] = conn
```

This is safe **within a fiber** but the tests verify:
- No leakage between fibers
- Proper cleanup after exceptions
- Correct behavior with fiber switching

## Reference Patterns

### Safe Lazy Initialization
```ruby
def connection_chain
  @connection_chain_mutex ||= Mutex.new
  @connection_chain_mutex.synchronize do
    @connection_chain ||= build_connection_chain
  end
end
```

### Safe Atomic Counter
```ruby
@middleware_version = Concurrent::AtomicFixnum.new(0)

def increment_middleware_version!
  @middleware_version.increment
end
```

### Safe Check-Then-Act
```ruby
@registration_mutex = Mutex.new

def register_middleware
  @registration_mutex.synchronize do
    return if @middleware_registered
    RedisClient.register(DatabaseLogger)
    @middleware_registered = true
  end
end
```

### Safe Caching
```ruby
require 'concurrent-ruby'
@cache = ThreadSafe::Cache.new

def get_or_create(key)
  @cache.fetch_or_store(key) { expensive_operation }
end
```

## Further Reading

- **Main Analysis**: `/THREAD_SAFETY_ANALYSIS.md` - Comprehensive findings and specific line numbers
- **Thread Safety Cheatsheet**: Project memory `cheatsheet_thread_safety_testing`
- **Concurrent Ruby**: https://github.com/ruby-concurrency/concurrent-ruby
- **Ruby Threads**: https://docs.ruby-lang.org/en/master/Thread.html

## Philosophy

These tests exist because **threading bugs are hard to find and reproduce**. They might work 999 times and fail on the 1000th. These tests create the worst-case scenario on every run, making the invisible visible.

A test suite without thread safety tests is like a car without crash tests - it might work fine until someone gets hurt.
