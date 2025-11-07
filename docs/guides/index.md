# Familia v2.0 Documentation

Welcome to the comprehensive documentation for Familia v2.0. This guide collection provides detailed explanations of all major features including security, connection management, architecture, and object relationships.

> **📖 Documentation Layers**
> - **[Overview](../overview.md)** - Conceptual introduction and getting started
> - **[Technical Reference](../reference/api-technical.md)** - Implementation patterns and technical details
> - **This Guide Collection** - Deep-dive topic guides with detailed prose and examples

## 📚 Guide Structure

### 🏗️ Architecture & System Design

1. **[Feature System](feature-system.md)** - Modular architecture with dependencies and autoloader patterns
2. **[Feature System for Developers](feature-system-devs.md)** - Advanced feature development patterns
3. **[Field System](field-system.md)** - Field definitions and data type mappings
4. **[Logging](logging.md)** - Logger configuration and database command logging


### 🔐 Security & Special Fields

5. **[Encrypted Fields](feature-encrypted-fields.md)** - Persistent encrypted storage with modular providers
6. **[Transient Fields](feature-transient-fields.md)** - Non-persistent secure data handling with RedactedString
7. **[Encryption Guide](encryption.md)** - Legacy encryption documentation
8. **[Object Identifiers](feature-object-identifiers.md)** - Automatic ID generation with configurable strategies
9. **[External Identifiers](feature-external-identifiers.md)** - Integration with external systems and legacy data


### 🔗 Object Relationships

10. **[Relationships](feature-relationships.md)** - Object relationships and membership system
11. **[Relationship Methods](feature-relationships-methods.md)** - Detailed method reference for relationships

### ⏱️ Time & Analytics Features

12. **[Expiration](feature-expiration.md)** - TTL management and cascading expiration
13. **[Quantization](feature-quantization.md)** - Time-based data bucketing for analytics
14. **[Time Literals](time-literals.md)** - Time manipulation and formatting utilities

### 🛠️ Implementation & Usage

15. **[Optimized Loading](optimized-loading.md)** - Reduce Redis commands by 50-96% for bulk object loading _(new!)_


## 🚀 Quick Start Examples

### Encrypted Fields (Persistent)
```ruby
class User < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :secret_recipe
end

# Configure encryption
Familia.configure do |config|
  config.encryption_keys = { v1: ENV['FAMILIA_ENCRYPTION_KEY'] }
  config.current_key_version = :v1
end

user = User.new(secret_recipe: "donna's cookies")
user.save
user.secret_recipe  # => "donna's cookies" (automatically decrypted)
```

### Feature System (Modular)
```ruby
class Customer < Familia::Horreum
  feature :safe_dump       # API-safe serialization
  feature :expiration      # TTL support
  feature :encrypted_fields # Secure storage

  field :name, :email
  encrypted_field :api_key
  default_expiration 24.hours
  safe_dump_fields :name, :email
end
```

### Connection Pooling (Performance)
```ruby
# Configure connection provider for multi-database pooling
Familia.connection_provider = lambda do |uri|
  parsed = URI.parse(uri) # => URI::Redis
  pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

  @pools[pool_key] ||= ConnectionPool.new(size: 10) do
    Redis.new(host: parsed.host, port: parsed.port, db: parsed.db || 0)
  end

  @pools[pool_key].with { |conn| conn }
end
```

### Object Relationships
```ruby
class Customer < Familia::Horreum
  feature :relationships
  identifier_field :custid
  field :custid, :name, :email
  set :domains  # Customer collections
end

class Domain < Familia::Horreum
  feature :relationships
  identifier_field :domain_id
  field :domain_id, :name, :dns_zone
  participates_in Customer, :domains  # Bidirectional membership
end

# Create objects and establish relationships
customer = Customer.new(custid: "cust123", name: "Acme Corp")
domain = Domain.new(domain_id: "dom456", name: "acme.com")

# Ruby-like syntax for relationships
customer.domains << domain  # Clean collection syntax

# Query relationships
domain.in_customer_domains?(customer.custid)  # => true
customer.domains.member?(domain.identifier)   # => true
```

### Object Identifiers (Auto-generation)
```ruby
class Document < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4
  field :title, :content
end

class Session < Familia::Horreum
  feature :object_identifier, generator: :hex
  field :user_id, :data
end

# Automatic ID generation
doc = Document.create(title: "My Document")
doc.objid  # => "f47ac10b-58cc-4372-a567-0e02b2c3d479"

session = Session.create(user_id: "123")
session.objid  # => "a1b2c3d4e5f6"
```

### External Identifiers (Legacy Integration)
```ruby
class ExternalUser < Familia::Horreum
  feature :external_identifier
  field :internal_id, :external_id, :name
end

# Map external system IDs to internal objects
user = ExternalUser.create(
  internal_id: SecureRandom.uuid,
  external_id: "ext_12345",
  name: "Legacy User"
)

# Find by external ID
found = ExternalUser.find_by_external_id("ext_12345")
```

### Quantization (Analytics)
```ruby
class MetricsBucket < Familia::Horreum
  feature :quantization
  field :metric_key, :value_count
  string :counter, quantize: [10.minutes, '%H:%M']
end

# Automatic time bucketing for analytics
MetricsBucket.record_event("page_view")  # Groups into 10-min buckets
```

### Optimized Loading (Performance)
```ruby
# Skip EXISTS check (50% reduction)
user = User.find_by_id(123, check_exists: false)

# Pipelined bulk loading (96% reduction for N objects)
metadata_ids = customer.metadata.rangebyscore(start_time, end_time)
# => ["id1", "id2", ..., "id14"]  # 14 metadata objects

# Traditional: 28 Redis commands (14 EXISTS + 14 HGETALL)
metadata = metadata_ids.map { |id| Metadata.find_by_id(id) }

# Optimized: 1 pipelined batch with 14 HGETALL commands
metadata = Metadata.load_multi(metadata_ids).compact
```


## Related Resources

- [Familia README](https://github.com/delano/familia) - Main project documentation
- [Issue #57](https://github.com/delano/familia/issues/57) - Original feature proposal
- [Issue #58](https://github.com/delano/familia/issues/58) - Wiki documentation tracking
