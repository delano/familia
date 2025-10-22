# Thread Safety Test Suite

## Purpose

This directory contains targeted tests that expose threading vulnerabilities in Familia's codebase. These tests were created following a systematic analysis that identified critical race conditions in production code that currently have no synchronization protection.

**Key Insight**: These tests are designed to **fail or expose inconsistencies** until the underlying code is fixed. A passing test here means the code has proper thread safety mechanisms (Mutex, AtomicFixnum, etc.) in place.

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

## Current Status

**Overall Coverage**: ~30% (target: ~85%)

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
