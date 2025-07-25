# Connection Pooling with Familia

Familia uses a flexible connection provider pattern that allows you to implement connection pooling in your application. This guide shows how to configure connection pools for optimal performance with multiple logical databases.

## Key Concepts

1. **Connection Provider Contract**: When you provide a `connection_provider`, it MUST return connections already on the correct logical database. Familia will NOT issue SELECT commands after receiving a connection from the provider.

2. **URI-based Selection**: Familia passes normalized URIs (e.g., `redis://localhost:6379/2`) to your provider, encoding the logical database in the URI.

3. **One Pool Per Database**: Since Familia models can use different logical databases, you typically need one connection pool per unique database.

## Basic Connection Pool Setup

### Example 1: Simple Connection Pool

```ruby
require 'connection_pool'
require 'familia'

class MyApp
  def self.setup_familia_pools
    @pools = {}

    Familia.connection_provider = lambda do |uri|
      parsed = URI.parse(uri)
      pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

      # Create a pool for each unique database
      @pools[pool_key] ||= ConnectionPool.new(size: 10, timeout: 5) do
        Redis.new(
          host: parsed.host,
          port: parsed.port,
          db: parsed.db || 0  # Connection created with correct DB
        )
      end

      # Return a connection from the pool
      @pools[pool_key].with { |conn| conn }
    end
  end
end
```

### Example 2: Advanced Pooling with Different Configurations

```ruby
class MyApp
  # Different pool sizes based on expected traffic
  POOL_CONFIGS = {
    0 => { size: 20, timeout: 5 },  # High-traffic main database
    1 => { size: 5, timeout: 5 },   # Low-traffic analytics database
    2 => { size: 10, timeout: 5 },  # Medium-traffic cache database
    3 => { size: 5, timeout: 5 }    # Session database
  }

  def self.setup_familia_pools
    @pools = {}

    Familia.connection_provider = lambda do |uri|
      parsed = URI.parse(uri)
      db = parsed.db || 0
      pool_key = "#{parsed.host}:#{parsed.port}/#{db}"

      @pools[pool_key] ||= begin
        config = POOL_CONFIGS[db] || { size: 5, timeout: 5 }
        ConnectionPool.new(**config) do
          Redis.new(host: parsed.host, port: parsed.port, db: db)
        end
      end

      @pools[pool_key].with { |conn| conn }
    end
  end
end
```

### Example 3: Using with Puma/Multi-threaded Servers

```ruby
# In config/initializers/familia.rb

# Global connection pools shared across threads
$redis_pools = {}
$pool_mutex = Mutex.new

Familia.connection_provider = lambda do |uri|
  parsed = URI.parse(uri)
  pool_key = parsed.to_s

  # Thread-safe pool creation
  $pool_mutex.synchronize do
    $redis_pools[pool_key] ||= ConnectionPool.new(
      size: ENV.fetch('RAILS_MAX_THREADS', 5).to_i,
      timeout: 5
    ) do
      Redis.new(
        host: parsed.host,
        port: parsed.port,
        db: parsed.db || 0,
        timeout: 1,  # Connection timeout
        reconnect_attempts: 3
      )
    end
  end

  $redis_pools[pool_key].with { |conn| conn }
end
```

### Example 4: Using with Sidekiq

```ruby
# Sidekiq has its own connection pool management
# This example shows how to share pools between Sidekiq and web processes

class RedisConnectionPools
  include Singleton

  def initialize
    @pools = {}
    @mutex = Mutex.new
  end

  def get_connection(uri)
    parsed = URI.parse(uri)
    pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

    pool = @mutex.synchronize do
      @pools[pool_key] ||= ConnectionPool.new(
        size: determine_pool_size,
        timeout: 5
      ) do
        Redis.new(
          host: parsed.host,
          port: parsed.port,
          db: parsed.db || 0
        )
      end
    end

    pool.with { |conn| conn }
  end

  private

  def determine_pool_size
    if defined?(Sidekiq)
      # Sidekiq workers need more connections
      Sidekiq.options[:concurrency] + 2
    else
      # Web processes need fewer connections
      ENV.fetch('RAILS_MAX_THREADS', 5).to_i
    end
  end
end

# Configure Familia
Familia.connection_provider = lambda do |uri|
  RedisConnectionPools.instance.get_connection(uri)
end
```

## Model Configuration

Models can specify different logical databases:

```ruby
# Models using different logical databases
class Customer < Familia::Horreum
  self.logical_database = 0  # Main application data
  field :name
  field :email
end

class Analytics < Familia::Horreum
  self.logical_database = 1  # Analytics data
  field :event_type
  field :timestamp
end

class Session < Familia::Horreum
  self.logical_database = 2  # Session/cache data
  feature :expiration
  default_expiration 1.hour
  field :user_id
  field :data
end

# Models can share the same logical database
class Order < Familia::Horreum
  self.logical_database = 0  # Shares DB with Customer
  field :customer_id
  field :total
end
```

## Performance Optimization

### Avoiding SELECT Command Overhead

Without proper pooling configuration, each Redis operation might issue a SELECT command:

```
# Bad: Without connection provider
SET key value     # Connection on DB 0
SELECT 2          # Switch to DB 2
SET key2 value2   # Now on DB 2
SELECT 0          # Switch back
GET key           # Now on DB 0
```

With the connection provider pattern:

```
# Good: With connection provider
SET key value     # Connection already on correct DB
SET key2 value2   # Different connection, already on correct DB
GET key           # Original connection, still on correct DB
```

### Pool Sizing Guidelines

1. **Web Applications**: `pool_size = number_of_threads + buffer`
   ```ruby
   size: ENV.fetch('RAILS_MAX_THREADS', 5).to_i + 2
   ```

2. **Background Jobs**: `pool_size = concurrency + buffer`
   ```ruby
   size: Sidekiq.options[:concurrency] + 5
   ```

3. **Mixed Workloads**: Size based on the logical database's usage pattern
   ```ruby
   POOL_CONFIGS = {
     0 => { size: 20 },  # High-traffic main DB
     1 => { size: 5 },   # Low-traffic analytics
     2 => { size: 15 }   # Medium-traffic cache
   }
   ```

## Testing Your Configuration

```ruby
# Test helper to verify pools are working correctly
class ConnectionPoolTester
  def self.test_pools
    # Create test models using different databases
    class TestModel0 < Familia::Horreum
      self.logical_database = 0
      field :value
    end

    class TestModel1 < Familia::Horreum
      self.logical_database = 1
      field :value
    end

    # Test concurrent access
    threads = 10.times.map do |i|
      Thread.new do
        100.times do |j|
          # This should use the pool for DB 0
          TestModel0.create(value: "thread-#{i}-#{j}")

          # This should use the pool for DB 1
          TestModel1.create(value: "thread-#{i}-#{j}")
        end
      end
    end

    threads.each(&:join)
    puts "Pool test completed successfully"
  end
end
```

## Monitoring and Debugging

Enable debug mode to verify connection providers are returning connections on the correct database:

```ruby
Familia.debug = true  # Logs warnings if provider returns wrong DB
```

Monitor pool usage:

```ruby
# Add monitoring to your connection provider
Familia.connection_provider = lambda do |uri|
  pool = get_pool_for(uri)

  # Log pool statistics
  Rails.logger.info "Pool stats: #{pool.size} size, #{pool.available} available"

  pool.with { |conn| conn }
end
```

## Common Pitfalls

1. **Not returning DB-ready connections**: Your provider MUST return connections already on the correct database.

2. **Creating too many pools**: Ensure you're keying pools correctly to avoid creating duplicate pools for the same database.

3. **Forgetting thread safety**: Pool creation should be thread-safe in multi-threaded environments.

4. **Incorrect pool sizing**: Monitor your connection usage and adjust pool sizes accordingly.

## Summary

- Familia delegates connection management to your application via `connection_provider`
- Providers must return connections already on the correct logical database
- Use the `connection_pool` gem for robust pooling
- Create one pool per unique logical database
- Monitor and tune pool sizes based on your workload
