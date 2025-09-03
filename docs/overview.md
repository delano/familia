
# Familia - Overview

> [!NOTE]
> This document refers to Valkey throughout, but all examples and patterns work identically with Redis. Familia supports both Valkey and Redis as they share the same protocol and data structures.

## Introduction

Familia is a Ruby ORM for Valkey (Redis) that provides object-oriented access to Valkey's native data structures. Unlike traditional ORMs that map objects to relational tables, Familia preserves Valkey's performance and flexibility while offering a familiar Ruby interface.

**Why Familia?**
- Maps Ruby objects directly to Valkey's native data structures (strings, lists, sets, etc.)
- Maintains Valkey's atomic operations and performance characteristics
- Handles complex patterns (quantization, encryption, expiration) out of the box

## Core Concepts

### What is a Horreum Class?

The ```Horreum``` class is Familia's foundation, representing Valkey-compatible objects. It's named after ancient Roman storehouses, reflecting its purpose as a structured data repository.

```ruby
class Flower < Familia::Horreum
  identifier_field :token
  field :name
  field :color
  field :species
  list :owners
  set :tags
  zset :metrics
  hashkey :props
  string :counter
end
```

This pattern lets you work with Valkey data as Ruby objects while maintaining direct access to Valkey's native operations.

### Flexible Identifiers

Horreum classes require identifiers to determine Valkey key names. You can define them in various ways:

```ruby
class User < Familia::Horreum
  # Simple field-based identifier
  identifier_field :email

  # Computed identifier
  identifier_field ->(user) { "user:#{user.id}" }

  # Multi-field composite identifier
  identifier_field [:type, :email]

  field :email
  field :type
  field :id
end
```

This flexibility allows you to adapt to different Valkey key naming strategies while maintaining clean Ruby object interfaces.

### Data Types Mapping

Familia provides direct mappings to Valkey's native data structures:

```ruby
class Product < Familia::Horreum
  identifier_field :sku

  # Basic fields
  field :sku
  field :name
  field :price

  # String fields (for counters, simple values)
  string :view_count, default: '0'
  # Usage: view_count.increment (atomic increment)

  # Lists (ordered, allows duplicates)
  list :categories
  # Usage: categories.push('fruit'), categories.pop

  # Sets (unordered, unique)
  set :tags
  # Usage: tags.add('organic'), tags.include?('organic')

  # Sorted sets (scored, ordered)
  zset :ratings
  # Usage: ratings.add(4.5, 'customer123'), ratings.rank('customer123')

  # Hash keys (dictionaries)
  hashkey :attributes
  # Usage: attributes['color'] = 'red', attributes.to_h
end
```

Each type maintains Valkey's native operations while providing Ruby-friendly interfaces.

## Essential Features

### Automatic Expiration

Set default TTL for objects that should expire:

```ruby
class Session < Familia::Horreum
  feature :expiration
  default_expiration 30.minutes

  field :user_id
  field :token
end

# Auto-expires in 30 minutes
session = Session.create(user_id: '123', token: 'abc')
```

This is ideal for temporary data like authentication tokens or cache entries.

### Safe Dumping for APIs

Control which fields are exposed when serializing objects using the clean DSL:

```ruby
class User < Familia::Horreum
  feature :safe_dump

  # Use clean DSL methods instead of @safe_dump_fields
  safe_dump_field :id
  safe_dump_field :email
  safe_dump_field :full_name, ->(user) { "#{user.first_name} #{user.last_name}" }

  field :id, :email, :first_name, :last_name, :password_hash
end

user.safe_dump
#=> {id: "123", email: "alice@example.com", full_name: "Alice Smith"}
```

The new DSL prevents accidental exposure of sensitive data and makes field definitions easier to organize in feature modules.

### Time-based Quantization

Group time-based metrics into buckets:

```ruby
class DailyMetric < Familia::Horreum
  feature :quantization
  string :counter, default_expiration: 1.day, quantize: [10.minutes, '%H:%M']
end
```

This automatically groups metrics into 10-minute intervals formatted as "HH:MM", ideal for analytics dashboards.

## Advanced Patterns

### Custom Methods and Logic

Add domain-specific behavior to your models:

```ruby
class User < Familia::Horreum
  field :first_name
  field :last_name
  field :status

  def full_name
    "#{first_name} #{last_name}"
  end

  def active?
    status == 'active'
  end
end
```

These methods work alongside Familia's persistence layer, letting you build rich domain models.

### Transactional Operations

Execute multiple Valkey commands atomically:

```ruby
user.transaction do |conn|
  conn.set("user:#{user.id}:status", "active")
  conn.zadd("active_users", Time.now.to_i, user.id)
end
```

Preserves data integrity for complex operations that require multiple Valkey commands.

### Connection Management and Pooling

Configure connection pooling for production environments:

```ruby
require 'connection_pool'

pools = {
  "redis://localhost:6379/0" => ConnectionPool.new(size: 10) { Redis.new(db: 0) }
}

Familia.connection_provider = lambda do |uri|
  pool = pools[uri]
  pool.with { |conn| conn }
end
```

This ensures efficient Valkey connection usage in multi-threaded applications.

### Encrypted Fields

Protect sensitive data at rest:

```ruby
class SecureUser < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id
  field :email                    # Plain text
  encrypted_field :ssn            # Encrypted
  encrypted_field :notes, aad_fields: [:id, :email]  # With auth data
end
```

Uses authenticated encryption to protect data while allowing selective field access.

### Open-ended Serialization

Customize how objects are serialized to Valkey:

```ruby
class JsonModel < Familia::Horreum
  def serialize_value
    JSON.generate(to_h)
  end

  def self.deserialize_value(data)
    new(**JSON.parse(data, symbolize_names: true))
  end
end
```

Enables integration with custom serialization formats beyond Familia's defaults.

## Configuration

### Basic Setup

```ruby
# Simple connection
Familia.uri = 'redis://localhost:6379/0'

# Multiple databases
Familia.redis_config = {
  host: 'localhost',
  port: 6379,
  db: 0,
  timeout: 5
}
```

### Encryption Setup (Optional)

```ruby
# Generate base64-encoded 32-byte keys
Familia.config.encryption_keys = {
  v1: Base64.strict_encode64(SecureRandom.bytes(32)),
  v2: Base64.strict_encode64(SecureRandom.bytes(32))
}
Familia.config.current_key_version = :v2
```

## Common Patterns

### Bulk Operations

```ruby
# Load multiple objects
users = User.multiget('alice@example.com', 'bob@example.com')

# Batch operations
User.transaction do |conn|
  conn.set('user:alice:status', 'active')
  conn.zadd('active_users', Time.now.to_i, 'alice')
end
```

### Error Handling

```ruby
begin
  user = User.load('nonexistent@example.com')
rescue Familia::Problem => e
  puts "User not found: #{e.message}"
end

# Safe loading
user = User.load('maybe@example.com') || User.new
```

## Troubleshooting

### Common Issues

**Connection Errors:**
```ruby
# Check connection
Familia.connect_to_uri('redis://localhost:6379/0')
```

**Missing Keys:**
```ruby
# Debug key names
user = User.new(email: 'test@example.com')
puts user.rediskey  # Shows the Valkey key that would be used
```

**Encryption Issues:**
```ruby
# Validate encryption config
Familia::Encryption.validate_configuration!
```

### Debug Mode

```ruby
# Enable debug logging
Familia.debug = true

# Check what's in Valkey
Familia.redis.keys('*')  # List all keys (use carefully in production)
```

## Testing

### Test Configuration

```ruby
# test_helper.rb or spec_helper.rb
require 'familia'

# Use separate test database
Familia.uri = 'redis://localhost:6379/15'

# Setup encryption for tests
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clear data between tests
def clear_redis
  Familia.redis.flushdb
end
```
