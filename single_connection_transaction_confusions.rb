
# Here's a demonstration showing how mixing Redis modes on a single connection causes problems:

# This demonstration shows why you need careful mode management when sharing a single Redis connection. The key problems are:
#
# 1. **MULTI mode returns "QUEUED"** instead of actual values, breaking conditional logic
# 2. **Pipeline mode returns Futures** that can't be used immediately
# 3. **Nested transactions error out** completely
# 4. **Business logic fails silently** when it expects immediate execution but gets queuing
# 5. **Mode assumptions break** when code doesn't know what mode the connection is in
#
# This is why most production systems either:
# - Use connection pooling with fresh connections per operation
# - Explicitly track and enforce connection modes
# - Never share connections between different operation types
#
# https://kagi.com/assistant/ad4ad5d3-a906-4932-8f7b-a8c5d3da4c5a

require 'redis'

# Setup
redis = Redis.new(host: 'localhost', port: 6379)
redis.flushdb  # Clear for clean demo

# Set initial values
redis.set("counter", "10")
redis.set("name", "Alice")

puts "=== Initial State ==="
puts "counter: #{redis.get("counter")}"
puts "name: #{redis.get("name")}"
puts

# DEMONSTRATION 1: Commands during MULTI/EXEC are queued, not executed
puts "=== Demo 1: Commands inside MULTI don't execute immediately ==="
redis.multi do |conn|
  puts "Inside MULTI block..."

  # These commands are QUEUED, not executed
  conn.incr("counter")
  result = conn.get("counter")  # This returns "QUEUED", not the value!

  puts "Result of GET inside MULTI: #{result.inspect}"  # Prints "QUEUED"
  puts "Trying direct redis.get: #{redis.get("counter")}"  # Still shows "10"!

  # This will ALSO be queued - creating confusion
  conn.set("name", "Bob")
end

puts "After MULTI/EXEC:"
puts "counter: #{redis.get("counter")}"  # Now shows "11"
puts "name: #{redis.get("name")}"  # Now shows "Bob"
puts

# DEMONSTRATION 2: Nested MULTI causes errors
puts "=== Demo 2: Nested MULTI causes errors ==="
begin
  redis.multi do |conn|
    puts "In first MULTI..."
    conn.incr("counter")

    # This will raise an error!
    redis.multi do |inner|
      puts "Trying nested MULTI..."
      inner.incr("counter")
    end
  end
rescue Redis::CommandError => e
  puts "ERROR: #{e.message}"  # "ERR MULTI calls can not be nested"
end
puts

# DEMONSTRATION 3: Mixing pipeline and MULTI
puts "=== Demo 3: Pipeline and MULTI confusion ==="
redis.set("counter", "20")

results = redis.pipelined do |pipeline|
  pipeline.get("counter")  # Returns a Future

  # This seems like it should work, but...
  pipeline.multi do |multi|
    multi.incr("counter")
    multi.incr("counter")
  end  # The MULTI/EXEC happens inside the pipeline

  pipeline.get("counter")  # What value will this see?
end

puts "Pipeline results: #{results.inspect}"
# Output: ["20", "OK", ["21", "22"], "QUEUED", "QUEUED", ["21", "22"], "22"]
# Notice the confusing mix of values and "QUEUED" responses
puts

# DEMONSTRATION 4: Connection state corruption
puts "=== Demo 4: Interrupted MULTI leaves connection in bad state ==="
redis.set("value1", "100")

begin
  redis.multi do |conn|
    conn.incr("value1")

    # Simulate an error mid-transaction
    raise "Something went wrong!"

    conn.incr("value1")  # This never executes
  end
rescue => e
  puts "Caught error: #{e.message}"

  # Redis automatically DISCARD on exception, but let's verify state
  puts "value1 after failed transaction: #{redis.get("value1")}"  # Still "100"
end
puts

# DEMONSTRATION 5: Real-world confusion with shared connection
puts "=== Demo 5: Shared connection mode confusion ==="

class OrderService
  def initialize(redis_conn)
    @redis = redis_conn
  end

  def process_order(order_id)
    # Expects to run normal commands
    @redis.set("order:#{order_id}:status", "processing")

    # But if called inside a transaction, this gets QUEUED!
    status = @redis.get("order:#{order_id}:status")

    if status == "processing"  # This comparison fails if inside MULTI!
      @redis.set("order:#{order_id}:confirmed", "true")
    else
      puts "UNEXPECTED: Status is #{status.inspect}, not 'processing'"
    end
  end
end

service = OrderService.new(redis)

# Normal operation - works fine
puts "Normal operation:"
service.process_order(1)
puts "Order 1 confirmed: #{redis.get("order:1:confirmed")}"  # "true"

# Inside transaction - breaks!
puts "\nInside transaction:"
redis.multi do |conn|
  service2 = OrderService.new(conn)  # Same connection, MULTI mode
  service2.process_order(2)
end
puts "Order 2 confirmed: #{redis.get("order:2:confirmed")}"  # nil - logic failed!
puts

# DEMONSTRATION 6: Pipeline mode confusion
puts "=== Demo 6: Pipeline returns Futures, not values ==="
redis.set("score", "50")

redis.pipelined do |pipeline|
  current_score = pipeline.get("score")  # Returns a Redis::Future, not "50"

  # This doesn't work as expected!
  if current_score.to_i > 40  # Future doesn't respond to to_i properly
    pipeline.set("high_score", "true")
  end
end
# The if statement always executes because Future is truthy!

# Correct way requires waiting for pipeline to complete:
results = redis.pipelined do |pipeline|
  pipeline.get("score")
end
current_score = results[0]  # Now we have the actual value
puts "Score from pipeline: #{current_score}"
puts

# DEMONSTRATION 7: The worst case - mode switching mid-operation
puts "=== Demo 7: Mode switching breaks assumptions ==="

def update_stats(redis_conn, key)
  current = redis_conn.get(key).to_i

  # Some complex logic here...
  new_value = current + 10

  redis_conn.set(key, new_value)
  redis_conn.get(key)  # Expect to see new_value
end

redis.set("stats", "5")

# Normal mode - works
result = update_stats(redis, "stats")
puts "Normal mode result: #{result}"  # "15"

# Transaction mode - broken
redis.set("stats", "5")
redis.multi do |conn|
  result = update_stats(conn, "stats")
  puts "Transaction mode result: #{result.inspect}"  # "QUEUED" - not "15"!
end

puts "\n=== Summary ==="
puts "Redis connections have three modes:"
puts "1. Normal: Commands execute immediately, return values"
puts "2. MULTI: Commands queue, return 'QUEUED', execute on EXEC"
puts "3. Pipeline: Commands buffer, return Futures, execute together"
puts "\nMixing modes on one connection causes:"
puts "- Logic errors (comparisons with 'QUEUED' or Futures)"
puts "- Nested transaction errors"
puts "- Unexpected execution order"
puts "- Silent failures in business logic"
```
