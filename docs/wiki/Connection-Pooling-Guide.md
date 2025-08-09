# Connection Pooling Guide

## Overview

Familia provides robust connection pooling through a provider pattern that enables efficient Redis/Valkey connection management with support for multiple logical databases, thread safety, and optimal performance.

## Core Concepts

### Connection Provider Contract

Your connection provider **MUST** follow these rules:

1. **Database Selection**: Return connections already on the correct logical database
2. **No SELECT Commands**: Familia will NOT issue `SELECT` commands
3. **URI-based Selection**: Accept normalized URIs (e.g., `redis://localhost:6379/2`)
4. **Thread Safety**: Handle concurrent access safely

### Connection Priority System

Familia uses a three-tier connection resolution system:

1. **Thread-local connections** (middleware pattern)
2. **Connection provider** (if configured)
3. **Fallback behavior** (legacy direct connections, if allowed)

```ruby
# Priority 1: Thread-local (set by middleware)
Thread.current[:familia_connection] = redis_client

# Priority 2: Connection provider
Familia.connection_provider = ->(uri) { pool.checkout(uri) }

# Priority 3: Fallback (can be disabled)
Familia.connection_required = true  # Disable fallback
```

## Basic Setup

### Simple Connection Pool

```ruby
require 'connection_pool'

class ConnectionManager
  @pools = {}

  # Configure provider at application startup
  def self.setup!
    Familia.connection_provider = lambda do |uri|
      parsed = URI.parse(uri)
      pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

      @pools[pool_key] ||= ConnectionPool.new(size: 10, timeout: 5) do
        Redis.new(
          host: parsed.host,
          port: parsed.port,
          db: parsed.db || 0  # CRITICAL: Set DB on connection creation
        )
      end

      @pools[pool_key].with { |conn| conn }
    end
  end
end

# Initialize at app startup
ConnectionManager.setup!
```

### Multi-Database Configuration

```ruby
class DatabasePoolManager
  POOL_CONFIGS = {
    0 => { size: 20, timeout: 5 },  # Main application data
    1 => { size: 5,  timeout: 3 },  # Analytics/reporting
    2 => { size: 10, timeout: 2 },  # Session/cache data
    3 => { size: 15, timeout: 5 }   # Background jobs
  }.freeze

  @pools = {}

  def self.setup!
    Familia.connection_provider = lambda do |uri|
      parsed = URI.parse(uri)
      db = parsed.db || 0
      server = "#{parsed.host}:#{parsed.port}"
      pool_key = "#{server}/#{db}"

      @pools[pool_key] ||= begin
        config = POOL_CONFIGS[db] || { size: 5, timeout: 5 }

        ConnectionPool.new(**config) do
          Redis.new(
            host: parsed.host,
            port: parsed.port,
            db: db,
            timeout: 1,
            reconnect_attempts: 3,
            inherit_socket: false
          )
        end
      end

      @pools[pool_key].with { |conn| conn }
    end
  end
end
```

## Advanced Patterns

### Rails/Sidekiq Integration

```ruby
# config/initializers/familia_pools.rb
class FamiliaPoolManager
  include Singleton

  def initialize
    @pools = {}
    setup_connection_provider
  end

  private

  def setup_connection_provider
    Familia.connection_provider = lambda do |uri|
      get_connection(uri)
    end
  end

  def get_connection(uri)
    parsed = URI.parse(uri)
    pool_key = connection_key(parsed)

    @pools[pool_key] ||= create_pool(parsed)
    @pools[pool_key].with { |conn| conn }
  end

  def connection_key(parsed_uri)
    "#{parsed_uri.host}:#{parsed_uri.port}/#{parsed_uri.db || 0}"
  end

  def create_pool(parsed_uri)
    db = parsed_uri.db || 0

    ConnectionPool.new(
      size: pool_size_for_database(db),
      timeout: 5
    ) do
      Redis.new(
        host: parsed_uri.host,
        port: parsed_uri.port,
        db: db,
        timeout: redis_timeout,
        reconnect_attempts: 3
      )
    end
  end

  def pool_size_for_database(db)
    case db
    when 0 then sidekiq_concurrency + web_concurrency + 2  # Main DB
    when 1 then 5                                          # Analytics
    when 2 then web_concurrency + 2                        # Sessions
    else 5                                                  # Default
    end
  end

  def sidekiq_concurrency
    defined?(Sidekiq) ? Sidekiq.options[:concurrency] : 0
  end

  def web_concurrency
    ENV.fetch('WEB_CONCURRENCY', 5).to_i
  end

  def redis_timeout
    Rails.env.production? ? 1 : 5
  end
end

# Initialize the pool manager
FamiliaPoolManager.instance
```

### Request-Scoped Connections (Middleware)

```ruby
# Middleware for per-request connection management
class FamiliaConnectionMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Provide a single connection for the entire request
    ConnectionPool.with do |conn|
      Thread.current[:familia_connection] = conn
      @app.call(env)
    end
  ensure
    Thread.current[:familia_connection] = nil
  end
end

# In your Rack/Rails app
use FamiliaConnectionMiddleware
```

## Model Database Configuration

Configure models to use specific logical databases:

```ruby
class Customer < Familia::Horreum
  self.logical_database = 0  # Primary application data
  field :name, :email, :status
end

class AnalyticsEvent < Familia::Horreum
  self.logical_database = 1  # Separate analytics database
  field :event_type, :user_id, :timestamp, :properties
end

class SessionData < Familia::Horreum
  self.logical_database = 2  # Fast cache database
  feature :expiration
  default_expiration 1.hour
  field :user_id, :data, :csrf_token
end

class BackgroundJob < Familia::Horreum
  self.logical_database = 3  # Job queue database
  field :job_type, :payload, :status, :retry_count
end
```

## Performance Benefits

### Without Connection Pooling

Each operation may trigger database switches:

```ruby
# These operations might use different connections, causing SELECT commands:
customer = Customer.find(123)        # SELECT 0, then query
session = SessionData.find(456)     # SELECT 2, then query
analytics = AnalyticsEvent.find(789) # SELECT 1, then query
```

### With Connection Pooling

Connections stay on the correct database:

```ruby
# Each model uses its dedicated connection pool:
customer = Customer.find(123)        # Connection already on DB 0
session = SessionData.find(456)     # Different connection, already on DB 2
analytics = AnalyticsEvent.find(789) # Different connection, already on DB 1
```

## Pool Sizing Guidelines

### Web Applications
- **Formula**: `(threads_per_process * processes) + buffer`
- **Puma**: `(threads * workers) + 2`
- **Unicorn**: `processes + 2`

### Background Jobs
- **Sidekiq**: `concurrency + 2`
- **DelayedJob**: `worker_processes + 2`

### Database-Specific Sizing
```ruby
def pool_size_for_database(db)
  base_size = web_concurrency + sidekiq_concurrency

  case db
  when 0 then base_size + 5      # Main DB: highest usage
  when 1 then 3                  # Analytics: batch operations
  when 2 then base_size + 2      # Sessions: per-request access
  when 3 then sidekiq_concurrency # Jobs: worker access only
  else 5                         # Default for new DBs
  end
end
```

## Monitoring and Debugging

### Enable Debug Mode

```ruby
Familia.debug = true
# Shows database selection and connection provider usage
```

### Pool Usage Monitoring

```ruby
class PoolMonitor
  def self.stats
    FamiliaPoolManager.instance.instance_variable_get(:@pools).map do |key, pool|
      {
        database: key,
        size: pool.size,
        available: pool.available,
        checked_out: pool.size - pool.available
      }
    end
  end

  def self.health_check
    stats.each do |stat|
      utilization = (stat[:checked_out] / stat[:size].to_f) * 100
      puts "DB #{stat[:database]}: #{utilization.round(1)}% utilized"
      warn "High utilization!" if utilization > 80
    end
  end
end
```

### Connection Testing

```ruby
# Test concurrent access patterns
def test_concurrent_access
  threads = 20.times.map do |i|
    Thread.new do
      50.times do |j|
        Customer.create(name: "test-#{i}-#{j}")
        SessionData.create(user_id: i, data: "session-#{j}")
      end
    end
  end

  threads.each(&:join)
  puts "Concurrent test completed"
end
```

## Troubleshooting

### Common Issues

**1. Wrong Database Connections**
```ruby
# Problem: Provider not setting DB correctly
Redis.new(host: 'localhost', port: 6379)  # Missing db: parameter

# Solution: Always specify database
Redis.new(host: 'localhost', port: 6379, db: parsed_uri.db || 0)
```

**2. Pool Exhaustion**
```ruby
# Monitor pool usage
ConnectionPool.stats  # If available
# Increase pool size or reduce hold time
```

**3. Connection Leaks**
```ruby
# Always use .with for pool connections
pool.with do |conn|
  # Use connection
end

# Never checkout without returning
conn = pool.checkout  # ❌ Can leak
```

### Error Handling

```ruby
Familia.connection_provider = lambda do |uri|
  begin
    get_pooled_connection(uri)
  rescue Redis::ConnectionError => e
    # Log error, potentially retry or fall back
    Familia.logger.error "Connection failed: #{e.message}"
    raise Familia::ConnectionError, "Pool connection failed"
  end
end
```

## Best Practices

1. **Return Pre-Selected Connections**: Provider must return connections on the correct DB
2. **One Pool Per Database**: Each logical DB needs its own pool
3. **Thread Safety**: Use thread-safe pool creation and access
4. **Monitor Usage**: Track pool utilization and adjust sizes
5. **Proper Sizing**: Account for all concurrent access patterns
6. **Error Handling**: Gracefully handle connection failures
7. **Connection Validation**: Verify connections are healthy before use

## Integration Examples

### Roda Application

```ruby
class App < Roda
  plugin :hooks

  before do
    # Connection pooling handled automatically via provider
    # Each request gets appropriate connections per database
  end

  route do |r|
    r.get 'customers', Integer do |id|
      customer = Customer.find(id)        # Uses DB 0 pool
      session = SessionData.find(r.env)  # Uses DB 2 pool

      render_json(customer: customer, session: session)
    end
  end
end
```

### Background Jobs

```ruby
class ProcessCustomerJob
  include Sidekiq::Worker

  def perform(customer_id)
    # Each of these uses appropriate database pool
    customer = Customer.find(customer_id)           # DB 0
    SessionData.expire_for_user(customer_id)       # DB 2
    AnalyticsEvent.track('job.completed', user: customer_id)  # DB 1
  end
end
```

This connection pooling system provides the foundation for scalable, performant Familia applications with proper resource management across multiple logical databases.
