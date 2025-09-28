#!/usr/bin/env ruby
# examples/single_connection_transaction_confusions.rb

# Redis Single Connection Mode Confusions
#
# This file demonstrates why mixing Redis operation modes on a single connection
# causes subtle but critical failures in production applications.
#
# Key Concepts:
# - Normal mode: Commands execute immediately, return actual values
# - MULTI mode: Commands return "QUEUED", execute atomically on EXEC
# - Pipeline mode: Commands return Futures, execute in batch
#
# Production Impact:
# - Conditional logic breaks when expecting values but getting "QUEUED"
# - Business rules fail silently when code assumes immediate execution
# - Nested operations cause Redis protocol errors
# - Race conditions emerge from incorrect mode assumptions
#
# Key Insight: Connection source should determine which operations are
# allowed. This is how we prevent bugs like expecting values but getting "QUEUED".
#
# Summary of Behaviors:
#
#   | Handler | Transaction | Pipeline | Ad-hoc Commands |
#   |---------|------------|----------|-----------------|
#   | **FiberTransaction** | Reentrant (same conn) | Error | Use transaction conn |
#   | **FiberConnection** | Error | Error | ✓ Allowed |
#   | **Provider** | ✓ New checkout | ✓ New checkout | ✓ New checkout |
#   | **Default** | ✓ With guards | ✓ With guards | ✓ Check mode |
#   | **Create** | ✓ Fresh conn | ✓ Fresh conn | ✓ Fresh conn |
#
#
# Usage:
#
#   $ irb
#   load './single_connection_transaction_confusions.rb'
#   demo1_multi_queues_commands
#   demo2_nested_multi_fails
#   ...

require 'redis'

# Global Redis connection for demonstrations
$redis = Redis.new(host: 'localhost', port: 6379)

# Service class for demonstration 5
class OrderService
  def initialize(redis_conn)
    @redis = redis_conn
  end

  # This method assumes immediate command execution
  def process_order(order_id)
    # Step 1: Set processing status
    @redis.set("order:#{order_id}:status", 'processing')

    # Step 2: Verify status before proceeding (CRITICAL CHECK)
    status = @redis.get("order:#{order_id}:status")

    # Step 3: Conditional business logic
    if status == 'processing'
      @redis.set("order:#{order_id}:confirmed", 'true')
      puts "✅ Order #{order_id}: Status confirmed, order processed"
    else
      puts "❌ Order #{order_id}: Status check failed - got #{status.inspect}"
      # In production: would trigger error handling, alerts, etc.
    end
  end
end

def setup_redis_demo
  # Sets up clean Redis state for demonstrations
  $redis.flushdb
  $redis.set('counter', '10')
  $redis.set('name', 'Alice')
  $redis.set('score', '50')
  $redis.set('value1', '100')

  puts '=== Redis Demo Environment Ready ==='
  puts "counter: #{$redis.get('counter')}"
  puts "name: #{$redis.get('name')}"
  puts "score: #{$redis.get('score')}"
  puts
end

def demo1_multi_queues_commands
  # CRITICAL: Commands inside MULTI don't execute immediately
  #
  # Problem: Business logic expecting immediate results gets "QUEUED" instead
  # Impact: Conditional statements, calculations, and validations all break

  puts '=== Demo 1: Commands inside MULTI return "QUEUED", not values ==='

  $redis.multi do |conn|
    puts 'Inside MULTI block - all commands are queued...'

    # These increment counter but return "QUEUED"
    conn.incr('counter')
    result = conn.get('counter')

    puts "❌ GET inside MULTI returns: #{result.inspect} (expected: '11')"
    puts "❌ Direct redis.get still shows: #{$redis.get('counter')} (expected: '11')"

    # This condition will ALWAYS be false during MULTI
    if result == '11'
      puts '✅ Counter validation passed'
    else
      puts "⚠️  Counter validation failed - got #{result.inspect}, not '11'"
    end

    conn.set('name', 'Bob')
  end

  puts "\n📊 After MULTI/EXEC completes:"
  puts "counter: #{$redis.get('counter')} (now executed)"
  puts "name: #{$redis.get('name')} (now executed)"
  puts "\n💡 Lesson: Never use command results inside MULTI for logic\n\n"
end

def demo2_nested_multi_fails
  # CRITICAL: Redis protocol forbids nested MULTI commands
  #
  # Problem: Code reuse becomes impossible when methods assume fresh connections
  # Impact: Shared utilities break when called from within transactions

  puts '=== Demo 2: Nested MULTI causes Redis protocol errors ==='

  begin
    $redis.multi do |outer_conn|
      puts 'In outer MULTI transaction...'
      outer_conn.incr('counter')

      # This breaks the Redis protocol - MULTI calls cannot be nested
      $redis.multi do |inner_conn|
        puts 'Attempting inner MULTI...'
        inner_conn.incr('counter')
      end
    end
  rescue Redis::CommandError => e
    puts "❌ Redis Error: #{e.message}"
    puts '💡 This makes shared connection patterns dangerous'
  end

  puts "📊 Counter after error: #{$redis.get('counter')} (partial execution)\n\n"
end

def demo3_pipeline_multi_confusion
  # COMPLEX: Pipeline and MULTI modes create execution order confusion
  #
  # Problem: Commands execute in unexpected batches with mixed return types
  # Impact: Debugging becomes nearly impossible with interleaved operations

  puts '=== Demo 3: Pipeline + MULTI creates execution chaos ==='

  $redis.set('counter', '20')

  results = $redis.pipelined do |pipeline|
    # Returns Future object, not value
    pipeline.get('counter')

    # MULTI/EXEC block executes inside pipeline
    pipeline.multi do |multi|
      multi.incr('counter')  # Will be 21
      multi.incr('counter')  # Will be 22
    end

    # This sees the final value after MULTI completes
    pipeline.get('counter')
  end

  puts "📊 Pipeline results: #{results.inspect}"
  puts '🔍 Analysis:'
  puts "  - results[0]: Initial value ('20')"
  puts "  - results[1]: MULTI/EXEC result (['21', '22'])"
  puts "  - results[2]: Final value ('22')"
  puts "\n💡 Mixed return types make result processing error-prone\n\n"
end

def demo4_interrupted_multi_cleanup
  # RECOVERY: Redis auto-DISCARD on exceptions, but application state unclear
  #
  # Problem: Partial transaction state is invisible to application code
  # Impact: Error recovery logic may make incorrect assumptions about data state

  puts '=== Demo 4: Exception handling in MULTI transactions ==='

  $redis.set('value1', '100')
  original_value = $redis.get('value1')

  begin
    $redis.multi do |conn|
      conn.incr('value1') # Queued but not executed

      # Simulate business logic error
      raise StandardError, 'Payment validation failed'

      conn.incr('value1') # Never reached
    end
  rescue StandardError => e
    puts "🔥 Exception caught: #{e.message}"

    # Redis automatically DISCARD on exception
    current_value = $redis.get('value1')
    puts "📊 Value after exception: #{current_value} (#{current_value == original_value ? 'unchanged ✅' : 'modified ❌'})"
  end

  puts "💡 Redis auto-DISCARD protects consistency but masks partial state\n\n"
end

def demo5_shared_connection_logic_failure
  # PRODUCTION BUG: Business logic fails silently with shared connections
  #
  # Problem: Service classes can't detect when they're called inside transactions
  # Impact: Critical business rules execute incorrectly without visible errors

  puts '=== Demo 5: Shared connection breaks business logic ==='

  service = OrderService.new($redis)

  puts '📈 Normal operation:'
  service.process_order(1)
  puts "   Result: #{$redis.get('order:1:confirmed')}"

  puts "\n🔄 Inside MULTI transaction:"
  $redis.multi do |conn|
    # Same service class, but now connection is in MULTI mode
    transaction_service = OrderService.new(conn)
    transaction_service.process_order(2) # Logic fails silently
  end
  puts "   Result: #{$redis.get('order:2:confirmed')} (business logic bypassed!)"

  puts "\n💡 Service classes need connection mode awareness for safety\n\n"
end

def demo6_pipeline_future_confusion
  # TIMING: Pipeline returns Future objects that don't behave like values
  #
  # Problem: Conditional logic using Future objects produces unexpected results
  # Impact: Business rules execute incorrectly based on Future truthiness

  puts '=== Demo 6: Pipeline Futures break conditional logic ==='

  $redis.set('score', '30')

  puts '❌ Broken approach - using Future in conditional:'
  begin
    $redis.pipelined do |pipeline|
      current_score = pipeline.get('score') # Returns Redis::Future

      puts "   Future object: #{current_score.class}"
      puts "   Future value (immediate): #{current_score.inspect}"

      # This will cause an error - Future doesn't have to_i method
      if current_score.to_i > 40
        pipeline.set('achievement', 'high_score')
        puts '   ❌ Achievement awarded (incorrect - score is 30!)'
      end
    end
  rescue NoMethodError => e
    puts "   ❌ Error: #{e.message}"
    puts "   💡 Future objects don't behave like values!"
  end

  puts "\n✅ Correct approach - wait for pipeline completion:"
  results = $redis.pipelined do |pipeline|
    pipeline.get('score')
    pipeline.exists('achievement')
  end

  current_score = results[0].to_i
  has_achievement = results[1]

  puts "   Actual score: #{current_score}"
  puts "   Has achievement: #{has_achievement} (incorrect from above)"

  puts "\n💡 Always extract values from pipeline results before logic\n\n"
end

def demo7_mode_switching_catastrophe
  # CATASTROPHIC: Methods that switch connection modes mid-operation
  #
  # Problem: Utility functions work in normal mode but break in MULTI mode
  # Impact: Subtle bugs that only appear when code paths intersect

  puts '=== Demo 7: Mode switching breaks utility functions ==='

  # Utility function that assumes immediate execution
  def update_stats(redis_conn, key, increment = 10)
    # Read current value
    current = redis_conn.get(key).to_i
    puts "   📖 Read current value: #{current}"

    # Business logic
    new_value = current + increment
    puts "   🧮 Calculated new value: #{new_value}"

    # Write new value
    redis_conn.set(key, new_value)

    # Verification read (common pattern for critical updates)
    verified = redis_conn.get(key)
    puts "   ✅ Verification read: #{verified}"

    verified
  rescue NoMethodError => e
    puts "   ❌ Error: #{e.message}"
    puts '   💡 Function expects immediate values but got Future objects!'
    "ERROR: #{e.message}"
  end

  $redis.set('stats', '5')

  puts '📈 Normal mode - utility function works:'
  result = update_stats($redis, 'stats')
  puts "   Final result: #{result} ✅"

  puts "\n🔄 MULTI mode - same function breaks:"
  $redis.set('stats', '5') # Reset

  $redis.multi do |conn|
    result = update_stats(conn, 'stats')
    puts "   Final result: #{result.inspect} ❌ (expected: '15')"
  end

  # Check what actually happened
  actual_value = $redis.get('stats')
  puts "   Actual final value: #{actual_value}"

  puts "\n💡 Utility functions need explicit mode handling or connection isolation\n\n"
end

def summary_and_solutions
  # Summary of problems and production-ready solutions

  puts '=== Summary: Redis Connection Mode Problems ==='
  puts
  puts '🔴 PROBLEMS:'
  puts '  1. MULTI mode returns "QUEUED" instead of values'
  puts '  2. Pipeline mode returns Futures instead of values'
  puts '  3. Nested MULTI operations cause protocol errors'
  puts '  4. Business logic fails silently with wrong assumptions'
  puts '  5. Conditional statements break with mode confusion'
  puts '  6. Error recovery becomes unpredictable'
  puts
  puts '🟢 SOLUTIONS:'
  puts '  1. Connection pooling - fresh connection per operation type'
  puts '  2. Mode-aware service classes with explicit connection requirements'
  puts '  3. Never share connections between normal and transactional code'
  puts '  4. Use connection decorators that enforce mode contracts'
  puts '  5. Implement connection mode detection and validation'
  puts '  6. Design APIs that make mode requirements explicit'
  puts
  puts '📚 PRODUCTION PATTERNS:'
  puts '  - Repository pattern with mode-specific connections'
  puts '  - Command/Query separation with dedicated connection pools'
  puts '  - Transaction boundaries clearly defined at service layer'
  puts '  - Connection mode validation in development/testing'
  puts
end

# Main execution - run all demonstrations
if __FILE__ == $PROGRAM_NAME
  setup_redis_demo
  demo1_multi_queues_commands
  demo2_nested_multi_fails
  demo3_pipeline_multi_confusion
  demo4_interrupted_multi_cleanup
  demo5_shared_connection_logic_failure
  demo6_pipeline_future_confusion
  demo7_mode_switching_catastrophe
  summary_and_solutions

  puts '🎯 Demo complete! Load in IRB to run individual methods:'
  puts "   load './single_connection_transaction_confusions.rb'"
  puts '   demo1_multi_queues_commands'
  puts '   demo2_nested_multi_fails'
  puts '   # ... etc'
end
