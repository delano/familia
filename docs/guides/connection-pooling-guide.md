# Connection Pooling with Familia

Familia provides efficient Redis/Valkey connection management through a provider pattern that supports multiple logical databases, thread safety, and optimal performance.

## Connection Provider Contract

Your connection provider **MUST** follow these requirements:

1. **Return pre-selected connections**: Connections must already be on the correct logical database
2. **Accept normalized URIs**: Provider receives URIs like `redis://localhost:6379/2` with database encoded
3. **No SELECT commands**: Familia will NOT issue database selection commands
4. **Thread safety**: Handle concurrent access safely

## Connection Priority System

Familia uses a three-tier connection resolution:

1. **Thread-local connections** (middleware pattern) - highest priority
2. **Connection provider** (if configured) - second priority
3. **Fallback behavior** (legacy, can be disabled) - lowest priority

```ruby
# Priority 1: Thread-local (set by middleware)
Thread.current[:familia_connection] = redis_client

# Priority 2: Connection provider
Familia.connection_provider = ->(uri) { pool.checkout(uri) }

# Priority 3: Fallback control
Familia.connection_required = true  # Disable fallback, require external connections
```

## Basic Setup

### Simple Connection Pool

```ruby
require 'connection_pool'

class ConnectionManager
  @pools = {}

  def self.setup!
    Familia.connection_provider = lambda do |uri|
      parsed = URI.parse(uri)
      pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

      @pools[pool_key] ||= ConnectionPool.new(size: 10, timeout: 5) do
        Redis.new(
          host: parsed.host,
          port: parsed.port,
          db: parsed.db || 0  # CRITICAL: Set database on connection creation
        )
      end

      @pools[pool_key].with { |conn| conn }
    end
  end
end

# Initialize at application startup
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
      pool_key = "#{parsed.host}:#{parsed.port}/#{db}"

      @pools[pool_key] ||= begin
        config = POOL_CONFIGS[db] || { size: 5, timeout: 5 }

        ConnectionPool.new(**config) do
          Redis.new(
            host: parsed.host,
            port: parsed.port,
            db: db,
            timeout: 1,
            reconnect_attempts: 3
          )
        end
      end

      @pools[pool_key].with { |conn| conn }
    end
  end
end
```

### Production Setup with Auto-Sizing

```ruby
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
    pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

    @pools[pool_key] ||= ConnectionPool.new(
      size: pool_size_for_database(parsed.db || 0),
      timeout: 5
    ) do
      Redis.new(
        host: parsed.host,
        port: parsed.port,
        db: parsed.db || 0,
        timeout: 1,
        reconnect_attempts: 3
      )
    end

    @pools[pool_key].with { |conn| conn }
  end

  def pool_size_for_database(db)
    base_size = web_concurrency + sidekiq_concurrency

    case db
    when 0 then base_size + 5      # Main DB: highest usage
    when 1 then 5                  # Analytics: batch operations
    when 2 then base_size + 2      # Sessions: per-request access
    else 5                         # Default for new databases
    end
  end

  def web_concurrency
    ENV.fetch('WEB_CONCURRENCY', 5).to_i
  end

  def sidekiq_concurrency
    defined?(Sidekiq) ? Sidekiq.options[:concurrency] : 0
  end
end

# Initialize at startup
FamiliaPoolManager.instance
```

### Request-Scoped Connections (Middleware)

```ruby
class FamiliaConnectionMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Provide single connection for entire request
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
  logical_database 0  # Primary application data
  field :name, :email, :status
end

class AnalyticsEvent < Familia::Horreum
  logical_database 1  # Analytics database
  field :event_type, :user_id, :timestamp
end

class SessionData < Familia::Horreum
  logical_database 2  # Session cache
  feature :expiration
  default_expiration 1.hour
  field :user_id, :data
end

class BackgroundJob < Familia::Horreum
  logical_database 3  # Job queue database
  field :job_type, :payload, :status
end
```

## Performance Benefits

**Without connection pooling** - database switches for each operation:
```ruby
customer = Customer.find(123)        # SELECT 0, then query
session = SessionData.find(456)     # SELECT 2, then query
analytics = AnalyticsEvent.find(789) # SELECT 1, then query
```

**With connection pooling** - connections stay on correct database:
```ruby
customer = Customer.find(123)        # Connection already on DB 0
session = SessionData.find(456)     # Different connection, already on DB 2
analytics = AnalyticsEvent.find(789) # Different connection, already on DB 1
```

## Pool Sizing Guidelines

### Web Applications
- **Puma**: `(threads × workers) + 2`
- **Unicorn**: `worker_processes + 2`

### Background Jobs
- **Sidekiq**: `concurrency + 2`
- **DelayedJob**: `worker_processes + 2`

### Database-Specific Sizing
```ruby
def pool_size_for_database(db)
  case db
  when 0 then web_threads + sidekiq_threads + 5  # Main: high usage
  when 1 then 3                                  # Analytics: batch only
  when 2 then web_threads + 2                    # Sessions: per-request
  when 3 then sidekiq_threads                    # Jobs: worker access
  else 5                                         # Default
  end
end
```

## Monitoring & Debugging

### Enable Debug Mode
```ruby
Familia.debug = true
# Shows database selection and connection provider usage
```

### Pool Usage Monitoring
```ruby
class PoolMonitor
  def self.stats
    pools = FamiliaPoolManager.instance.instance_variable_get(:@pools)
    pools.map do |key, pool|
      {
        database: key,
        size: pool.size,
        available: pool.available,
        utilization: ((pool.size - pool.available) / pool.size.to_f * 100).round(1)
      }
    end
  end

  def self.health_check
    stats.each do |stat|
      warn "High utilization: #{stat[:database]} at #{stat[:utilization]}%" if stat[:utilization] > 80
    end
  end
end
```

### Connection Testing
```ruby
# Test concurrent access
def test_concurrent_pools
  threads = 10.times.map do |i|
    Thread.new do
      20.times { |j| Customer.create(name: "test-#{i}-#{j}") }
    end
  end
  threads.each(&:join)
end
```

## Troubleshooting

### Common Issues

**Wrong Database Connections**
```ruby
# ❌ Missing database specification
Redis.new(host: 'localhost', port: 6379)

# ✅ Always specify database
Redis.new(host: 'localhost', port: 6379, db: parsed_uri.db || 0)
```

**Pool Exhaustion**
- Monitor pool utilization
- Increase pool size or reduce connection hold time
- Check for connection leaks

**Connection Leaks**
```ruby
# ✅ Always use .with for connections
pool.with { |conn| conn.set('key', 'value') }

# ❌ Never checkout without returning
conn = pool.checkout  # Can leak connections
```

## Best Practices

1. **Provider Contract**: Return connections already on the correct database
2. **One Pool Per Database**: Each logical database needs its own pool
3. **Thread Safety**: Use thread-safe pool creation and access patterns
4. **Proper Sizing**: Account for all concurrent access patterns (web + jobs)
5. **Monitor Usage**: Track pool utilization and adjust sizes accordingly
6. **Error Handling**: Gracefully handle connection failures and timeouts
7. **Connection Validation**: Verify connections are healthy before use

This connection pooling system provides the foundation for scalable, performant Familia applications with efficient resource management across multiple logical databases.
