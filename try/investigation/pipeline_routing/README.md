# Pipeline Routing Investigation (ARCHIVED)

**Status**: Investigation complete - NO BUG FOUND
**Conclusion**: See `CONCLUSION.md` for full analysis
**Test Files**: Renamed to `.rb.txt` to preserve as documentation without running in CI

## Problem Statement (Original)

In a concurrent test with 20 threads executing pipelined operations, we observed:
- All 20 threads successfully complete
- All 20 commands are captured in `DatabaseLogger.commands`
- BUT: Only 16 commands contain the pipeline separator `' | '`
- This appeared to mean 4 pipeline operations were logged via `call()` instead of `call_pipelined()`

**Investigation Result**: Single-command pipelines don't have `' | '` separator (expected `Array#join` behavior). This is NOT a bug.

## Investigation Goals

1. Determine if this is a RedisClient middleware dispatch issue
2. Determine if this is a Familia connection chain issue
3. Determine if this is timing-dependent (race condition)
4. Determine if connection reuse vs. fresh connections affects behavior

## Test Suite Structure

### 01_single_thread_baseline_try.rb
**Purpose**: Establish baseline behavior in single-threaded environment

**Tests**:
- 10 simple pipeline operations
- 25 pipeline operations with varying sizes (1-5 commands)
- Mixed single and pipelined operations (10 each)

**Expected**: 100% of pipeline operations route to `call_pipelined()`

**Key Question**: Does single-threaded execution work correctly?

### 02_small_concurrency_try.rb
**Purpose**: Test with minimal thread contention (5 threads)

**Tests**:
- 5 threads with CyclicBarrier (synchronized start)
- 5 threads without barrier (natural timing)
- 5 threads with varying pipeline sizes (1-5 commands)

**Expected**: 100% of pipeline operations route to `call_pipelined()`

**Key Question**: Does adding concurrency break routing?

### 03_reproduce_issue_try.rb
**Purpose**: Reproduce the exact scenario from the original failing test

**Tests**:
- 20 threads with CyclicBarrier (exact reproduction)
- 10 repeated trials to check for intermittent behavior

**Expected**: May reproduce the routing issue

**Key Questions**:
- Is the issue reproducible?
- Is it deterministic or intermittent?
- What's the failure rate?

### 04_high_contention_try.rb
**Purpose**: Test under high thread contention (50+ threads)

**Tests**:
- 50 threads with synchronized start
- 50 threads with varying pipeline sizes (1-10 commands)
- 10 threads × 5 rapid pipelines each (50 total)

**Expected**: If timing-related, higher contention should increase failure rate

**Key Question**: Does the problem scale with thread count?

### 05_connection_isolation_try.rb
**Purpose**: Test whether the issue is connection-specific

**Tests**:
- Fresh connection per thread (each thread calls `Familia.dbclient`)
- Shared connection from main thread (original pattern)
- Isolated connections via `create_dbclient` (no pooling)
- Connection via chain per thread (uses connection handlers)

**Expected**: Identifies which connection pattern is problematic

**Key Questions**:
- Does connection reuse cause the issue?
- Does the connection chain have a bug?
- Is middleware registration timing-dependent?

### 06_fiber_state_inspection_try.rb
**Purpose**: Inspect Fiber-local state during pipeline operations

**Tests**:
- Single-threaded Fiber state tracking (before/inside/after pipeline)
- Multi-threaded Fiber isolation verification (10 threads)
- Middleware call context inspection (capture what middleware sees)
- Pipeline routing verification (ensure single `call_pipelined` per pipeline)

**Expected**: Fiber-local state should be isolated per thread

**Key Questions**:
- Is `Fiber[:familia_pipeline]` being set correctly?
- Is cleanup happening in ensure blocks?
- Do threads share Fiber state incorrectly?
- Does middleware receive correct context?

## Running the Tests

### Run all investigation tests
```bash
FAMILIA_DEBUG=0 bundle exec try --agent try/investigation/pipeline_routing/
```

### Run individual tests
```bash
# Baseline
bundle exec try --agent try/investigation/pipeline_routing/01_single_thread_baseline_try.rb

# Small concurrency
bundle exec try --agent try/investigation/pipeline_routing/02_small_concurrency_try.rb

# Reproduce issue
bundle exec try --agent try/investigation/pipeline_routing/03_reproduce_issue_try.rb

# High contention
bundle exec try --agent try/investigation/pipeline_routing/04_high_contention_try.rb

# Connection isolation
bundle exec try --agent try/investigation/pipeline_routing/05_connection_isolation_try.rb

# Fiber state
bundle exec try --agent try/investigation/pipeline_routing/06_fiber_state_inspection_try.rb
```

### Run with verbose output (for failures)
```bash
bundle exec try --verbose --fails --stack try/investigation/pipeline_routing/03_reproduce_issue_try.rb
```

## What to Look For

### Success Indicators
- All pipeline operations contain `' | '` separator
- Command counts match expected values
- No "ROUTING ANOMALY" messages in output

### Failure Indicators
- Pipeline operations logged without `' | '` separator
- Fewer `call_pipelined()` invocations than expected
- "ROUTING ANOMALY DETECTED" in output
- Mismatched command counts

### Diagnostic Output
Each test prints detailed analysis including:
- Total commands captured
- Pipeline commands (with separator)
- Single commands (without separator)
- Percentage breakdown
- Specific examples of misrouted commands

## Hypothesis Checklist

After running the tests, we should be able to answer:

- [ ] Does single-threaded execution work correctly?
- [ ] Does small concurrency (5 threads) work correctly?
- [ ] Can we reproduce the issue with 20 threads?
- [ ] Is the issue deterministic or intermittent?
- [ ] Does the problem scale with thread count?
- [ ] Is it related to connection reuse vs. fresh connections?
- [ ] Is it related to the connection chain implementation?
- [ ] Is Fiber-local state being managed correctly?
- [ ] Does middleware receive the correct context?

## Next Steps

Based on results:

1. **If baseline fails**: RedisClient middleware routing is broken in general
2. **If only concurrent tests fail**: Thread safety issue in middleware dispatch
3. **If only shared connection fails**: Connection chain or pooling issue
4. **If Fiber state leaks**: Cleanup logic in `PipelineCore` is broken
5. **If intermittent**: Race condition requiring deeper investigation

## Background: How Pipeline Routing Should Work

```ruby
# RedisClient source (redis-client-0.25.1/lib/redis_client.rb:446)
def pipelined(exception: true)
  pipeline = Pipeline.new(@command_builder)
  yield pipeline

  if pipeline._size == 0
    []
  else
    results = ensure_connected(retryable: pipeline._retryable?) do |connection|
      commands = pipeline._commands
      @middlewares.call_pipelined(commands, config) do  # <-- Should call this
        connection.call_pipelined(commands, pipeline._timeouts, exception: exception)
      end
    end

    pipeline._coerce!(results)
  end
end
```

**Expected flow**:
1. User calls `client.pipelined { |p| p.set(...) }`
2. RedisClient builds pipeline commands
3. RedisClient calls `@middlewares.call_pipelined(commands, config)`
4. DatabaseLogger.call_pipelined receives commands array
5. Logs with `' | '` separator joining commands

**Anomalous flow** (what we're seeing):
1. User calls `client.pipelined { |p| p.set(...) }`
2. ??? Something goes wrong ???
3. DatabaseLogger.call receives individual command
4. Logs without `' | '` separator

## Files Involved

- `/Users/d/Projects/opensource/d/familia/lib/middleware/database_logger.rb` - Middleware implementation
- `/Users/d/Projects/opensource/d/familia/lib/familia/connection.rb` - Connection management
- `/Users/d/Projects/opensource/d/familia/lib/familia/connection/pipelined_core.rb` - Pipeline execution
- `/Users/d/Projects/opensource/d/familia/try/unit/core/middleware_thread_safety_try.rb` - Original test that exposed this
