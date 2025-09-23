# Object Identifiers Guide

> **💡 Quick Reference**
>
> Enable automatic object ID generation with configurable strategies:
> ```ruby
> class Document < Familia::Horreum
>   feature :object_identifier, generator: :uuid_v4
>   field :title, :content
> end
> ```

## Overview

The Object Identifier feature provides automatic generation of unique identifiers for Familia objects. Instead of manually creating identifiers, you can configure different generation strategies that suit your application's needs - from globally unique UUIDs to compact hexadecimal strings.

## Why Use Object Identifiers?

**Consistency**: Ensures all objects have properly formatted, unique identifiers without manual management.

**Flexibility**: Different applications need different ID formats - UUIDs for distributed systems, short hex strings for internal tools, or custom formats for specific business requirements.

**Collision Avoidance**: Built-in collision detection and retry logic ensures identifier uniqueness even under high concurrency.

**Integration Ready**: Generated IDs work seamlessly with external APIs, logging systems, and database relationships.

## Quick Start

### Basic UUID Generation

```ruby
class User < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4

  field :name, :email, :created_at
end

# Automatic ID generation on creation
user = User.create(name: "Alice", email: "alice@example.com")
puts user.objid  # => "f47ac10b-58cc-4372-a567-0e02b2c3d479"
```

### Compact Hex Identifiers

```ruby
class Session < Familia::Horreum
  feature :object_identifier, generator: :hex, length: 16

  field :user_id, :data, :expires_at
end

session = Session.create(user_id: "user123")
puts session.objid  # => "a1b2c3d4e5f67890"
```

## Generator Types

### UUID v4 Generator

Standard UUID format providing global uniqueness across distributed systems.

```ruby
class Document < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4
  field :title, :content
end

doc = Document.create(title: "My Document")
doc.objid  # => "550e8400-e29b-41d4-a716-446655440000"
```

**Characteristics:**
- **Format**: 36 characters (8-4-4-4-12 hex pattern)
- **Uniqueness**: Globally unique across time and space
- **Performance**: Good for distributed systems
- **Use Cases**: Public APIs, microservices, external integrations

> **💡 Best Practice**
>
> Use UUID v4 for objects that will be exposed externally or across service boundaries.

### Hex Generator

Compact hexadecimal strings ideal for internal use and high-volume scenarios.

```ruby
class ApiKey < Familia::Horreum
  feature :object_identifier, generator: :hex, length: 24
  field :name, :permissions, :created_at
end

key = ApiKey.create(name: "Production API")
key.objid  # => "1a2b3c4d5e6f7890abcdef12"
```

**Configuration Options:**
- `length`: Number of hex characters (default: 12)
- `prefix`: Optional prefix for the identifier
- `charset`: Custom character set (default: hex digits)

```ruby
class InternalToken < Familia::Horreum
  feature :object_identifier,
          generator: :hex,
          length: 16,
          prefix: "tk_"

  field :scope, :issued_at
end

token = InternalToken.create(scope: "read:users")
token.objid  # => "tk_a1b2c3d4e5f67890"
```

**Characteristics:**
- **Format**: Configurable length hexadecimal string
- **Performance**: Very fast generation
- **Storage**: Compact representation
- **Use Cases**: Internal IDs, tokens, session identifiers

> **⚠️ Important**
>
> Hex generators provide good uniqueness but aren't globally unique like UUIDs. Use appropriate length for your collision tolerance.

### Custom Generator

Define your own identifier generation logic for business-specific requirements.

```ruby
class OrderNumber < Familia::Horreum
  feature :object_identifier, generator: :custom

  field :customer_id, :amount, :created_at

  # Custom generator implementation
  def self.generate_identifier
    timestamp = Time.now.strftime('%Y%m%d')
    sequence = Redis.current.incr("order_sequence:#{timestamp}")
    "ORD-#{timestamp}-#{sequence.to_s.rjust(6, '0')}"
  end
end

order = OrderNumber.create(customer_id: "cust123", amount: 99.99)
order.objid  # => "ORD-20241215-000001"
```

**Implementation Requirements:**
- Must define `self.generate_identifier` class method
- Should return a string identifier
- Must handle uniqueness and collision scenarios
- Consider thread safety for concurrent access

> **🔧 Advanced Pattern**
>
> Custom generators can integrate with external services, database sequences, or business rules for sophisticated ID schemes.

## Advanced Configuration

### Collision Detection

Enable automatic collision detection and retry logic:

```ruby
class Product < Familia::Horreum
  feature :object_identifier,
          generator: :hex,
          collision_check: true,
          max_retries: 5

  field :name, :price, :sku
end
```

**Configuration Options:**
- `collision_check`: Enable/disable collision detection (default: true)
- `max_retries`: Maximum retry attempts on collision (default: 3)
- `retry_delay`: Delay between retries in seconds (default: 0.001)

### Identifier Validation

Add custom validation logic for generated identifiers:

```ruby
class SecureToken < Familia::Horreum
  feature :object_identifier, generator: :custom

  def self.generate_identifier
    loop do
      candidate = SecureRandom.alphanumeric(32)
      # Ensure no ambiguous characters
      next if candidate.match?(/[0O1lI]/)
      return "st_#{candidate.downcase}"
    end
  end

  def self.valid_identifier?(id)
    id.match?(/^st_[a-z0-9]{32}$/) && !id.match?(/[0O1lI]/)
  end
end
```

## Performance Considerations

### Generation Speed Benchmarks

Different generators have varying performance characteristics:

```ruby
# Benchmark different generators
require 'benchmark'

Benchmark.bm(10) do |x|
  x.report("UUID v4:")    { 10_000.times { SecureRandom.uuid } }
  x.report("Hex 12:")     { 10_000.times { SecureRandom.hex(6) } }
  x.report("Hex 24:")     { 10_000.times { SecureRandom.hex(12) } }
  x.report("Custom:")     { 10_000.times { MyClass.generate_identifier } }
end
```

### Memory Usage

- **UUID v4**: 36 bytes per identifier
- **Hex**: Variable based on length (2 bytes per hex character)
- **Custom**: Depends on implementation

### Collision Probability

For hex generators, collision probability depends on length and volume:

```ruby
# Approximate collision probability for hex identifiers
def collision_probability(length, count)
  total_space = 16 ** length
  1 - Math.exp(-(count * (count - 1)) / (2.0 * total_space))
end

# Examples:
collision_probability(12, 1_000_000)   # Very low
collision_probability(8, 100_000)      # Consider longer length
```

> **📊 Sizing Guidance**
>
> - **8 hex chars**: Good for < 10K objects
> - **12 hex chars**: Good for < 1M objects
> - **16 hex chars**: Good for < 100M objects
> - **UUID v4**: Suitable for any scale

## Integration Patterns

### External API Integration

```ruby
class ExternalReference < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4
  field :external_id, :sync_status, :last_sync

  def sync_to_external_api
    response = ExternalAPI.create_record(
      id: self.objid,  # Use generated ID
      data: self.to_h
    )

    self.external_id = response['id']
    self.sync_status = 'synced'
    self.last_sync = Familia.now.to_i
    save
  end
end
```

### Database Relationships

```ruby
class Order < Familia::Horreum
  feature :object_identifier, generator: :custom
  field :customer_id, :total_amount

  def self.generate_identifier
    "ORD-#{SecureRandom.hex(8).upcase}"
  end
end

class OrderItem < Familia::Horreum
  feature :object_identifier, generator: :hex
  field :order_id, :product_id, :quantity

  def order
    Order.load(order_id)
  end
end

# Usage
order = Order.create(customer_id: "cust123", total_amount: 299.99)
item = OrderItem.create(
  order_id: order.objid,  # Reference by generated ID
  product_id: "prod456",
  quantity: 2
)
```

### Logging and Debugging

Generated identifiers provide excellent debugging context:

```ruby
class UserSession < Familia::Horreum
  feature :object_identifier, generator: :hex, length: 16
  field :user_id, :ip_address, :user_agent

  def log_activity(action)
    logger.info(
      "Session #{objid}: User #{user_id} performed #{action}",
      session_id: objid,
      user_id: user_id,
      action: action,
      timestamp: Familia.now.to_i
    )
  end
end
```

## Testing Strategies

### Test Identifier Generation

```ruby
# test/models/user_test.rb
require 'test_helper'

class UserTest < Minitest::Test
  def test_uuid_generation
    user = User.create(name: "Test User")

    # Verify UUID format
    assert_match(
      /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
      user.objid
    )
  end

  def test_hex_generation
    session = Session.create(user_id: "123")

    # Verify hex format and length
    assert_match(/\A[0-9a-f]{16}\z/i, session.objid)
    assert_equal 16, session.objid.length
  end

  def test_custom_identifier_format
    order = OrderNumber.create(customer_id: "cust123")

    # Verify custom format
    assert_match(/\AORD-\d{8}-\d{6}\z/, order.objid)
  end
end
```

### Mock Generators for Testing

```ruby
# test/test_helper.rb
class TestIdentifierGenerator
  def self.generate_test_uuid
    "test-#{Time.now.to_f}-#{rand(1000)}"
  end
end

# In tests
class User < Familia::Horreum
  feature :object_identifier, generator: :custom

  def self.generate_identifier
    if Rails.env.test?
      TestIdentifierGenerator.generate_test_uuid
    else
      SecureRandom.uuid
    end
  end
end
```

## Troubleshooting

### Common Issues

**Identifier Not Generated**
```ruby
# Ensure feature is enabled
class MyModel < Familia::Horreum
  feature :object_identifier  # This line is required!
  field :name
end
```

**Custom Generator Not Called**
```ruby
# Verify method signature
def self.generate_identifier  # Must be class method
  # Implementation here
end
```

**Collision Detection Failing**
```ruby
# Check Valkey/Redis connectivity and permissions
begin
  MyModel.create(name: "test")
rescue Familia::Problem => e
  puts "Identifier collision: #{e.message}"
end
```

### Debug Identifier Generation

```ruby
# Enable debug logging
Familia.debug = true

# Check feature configuration
MyModel.feature_options(:object_identifier)
#=> {generator: :uuid_v4, collision_check: true, max_retries: 3}

# Verify generation manually
MyModel.generate_identifier  # Should return new identifier
```

---

## See Also

- **[Technical Reference](../reference/api-technical.md#object-identifier-feature-v200-pre7)** - Implementation details and advanced patterns
- **[External Identifiers Guide](feature-external-identifiers.md)** - Integration with external systems
- **[Feature System Guide](feature-system.md)** - Understanding the feature architecture
- **[Implementation Guide](implementation.md)** - Advanced configuration patterns
