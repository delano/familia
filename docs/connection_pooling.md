# Connection Pooling with Familia

Familia uses a connection provider pattern for efficient connection pooling. This guide shows how to configure pools for optimal performance with multiple logical databases.

## Key Concepts

- **Connection Provider Contract**: Your provider MUST return connections already on the correct logical database. Familia will NOT issue SELECT commands.
- **URI-based Selection**: Familia passes normalized URIs (e.g., `redis://localhost:6379/2`) encoding the logical database.
- **One Pool Per Database**: Each unique logical database requires its own connection pool.

## Basic Setup

### Simple Connection Pool

```ruby
require 'connection_pool'

class MyApp
  @pools = {}

  Familia.connection_provider = lambda do |uri|
    parsed = URI.parse(uri)
    pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

    @pools[pool_key] ||= ConnectionPool.new(size: 10, timeout: 5) do
      Redis.new(
        host: parsed.host,
        port: parsed.port,
        db: parsed.db || 0
      )
    end

    @pools[pool_key].with { |conn| conn }
  end
end
```

### Multi-Database Configuration

```ruby
class MyApp
  POOL_CONFIGS = {
    0 => { size: 20 },  # Main database
    1 => { size: 5 },   # Analytics
    2 => { size: 10 }   # Cache
  }.freeze

  @pools = {}

  Familia.connection_provider = lambda do |uri|
    parsed = URI.parse(uri)
    db = parsed.db || 0
    pool_key = "#{parsed.host}:#{parsed.port}/#{db}"

    @pools[pool_key] ||= begin
      config = POOL_CONFIGS[db] || { size: 5 }
      ConnectionPool.new(timeout: 5, **config) do
        Redis.new(host: parsed.host, port: parsed.port, db: db)
      end
    end

    @pools[pool_key].with { |conn| conn }
  end
end
```

### Production Setup with Roda

```ruby
# config/familia.rb
class FamiliaPoolManager
  include Singleton

  def initialize
    @pools = {}
  end

  def get_connection(uri)
    parsed = URI.parse(uri)
    pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

    @pools[pool_key] ||= ConnectionPool.new(
      size: pool_size_for_environment,
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

  private

  def pool_size_for_environment
    if defined?(Sidekiq)
      Sidekiq.options[:concurrency] + 2
    else
      ENV.fetch('WEB_CONCURRENCY', 5).to_i + 2
    end
  end
end

# Configure at application startup
Familia.connection_provider = lambda do |uri|
  FamiliaPoolManager.instance.get_connection(uri)
end

# In your Roda app
class App < Roda
  plugin :hooks

  before do
    # Familia pools are automatically used via connection_provider
  end
end
```

## Model Configuration

Configure models to use different logical databases:

```ruby
class Customer < Familia::Horreum
  self.logical_database = 0  # Main application data
  field :name, :email
end

class Analytics < Familia::Horreum
  self.logical_database = 1  # Analytics data
  field :event_type, :timestamp
end

class Session < Familia::Horreum
  self.logical_database = 2  # Session/cache data
  feature :expiration
  default_expiration 1.hour
  field :user_id, :data
end
```

## Performance Benefits

Without connection pooling, each operation triggers database switches:
```
SET key value     # Connection on DB 0
SELECT 2          # Switch to DB 2
SET key2 value2   # Now on DB 2
SELECT 0          # Switch back
```

With proper pooling, connections stay on the correct database:
```
SET key value     # Connection already on DB 0
SET key2 value2   # Different connection, already on DB 2
```

## Pool Sizing Guidelines

- **Web Applications**: `threads + 2`
- **Background Jobs**: `concurrency + 2`
- **High Traffic DBs**: Scale up based on usage patterns

## Testing and Debugging

Enable debug mode to verify correct database selection:
```ruby
Familia.debug = true
```

Test concurrent access:
```ruby
threads = 10.times.map do |i|
  Thread.new do
    100.times { |j| MyModel.create(value: "test-#{i}-#{j}") }
  end
end
threads.each(&:join)
```

## Best Practices

- Return connections already on the correct database
- Use one pool per unique logical database
- Implement thread-safe pool creation
- Monitor pool usage and adjust sizes accordingly
- Use the `connection_pool` gem for production reliability
