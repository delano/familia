# Familia v2.0 Documentation

Welcome to the comprehensive documentation for Familia v2.0. This wiki covers all major features including security, connection management, architecture, and object relationships.

## 📚 Documentation Structure

### 🔐 Security & Data Protection

1. **[Encrypted Fields Overview](Encrypted-Fields-Overview.md)** - Persistent encrypted storage with modular providers
2. **[Transient Fields Guide](Transient-Fields-Guide.md)** - Non-persistent secure data handling with RedactedString
3. **[Security Model](Security-Model.md)** - Cryptographic design and Ruby memory limitations

### 🏗️ Architecture & System Design  

4. **[Feature System Guide](Feature-System-Guide.md)** - Modular architecture with dependencies and conflict resolution _(new!)_
5. **[Connection Pooling Guide](Connection-Pooling-Guide.md)** - Provider pattern for efficient Redis/Valkey pooling _(new!)_
6. **[RelatableObjects Guide](RelatableObjects-Guide.md)** - Object relationships and ownership system _(new!)_

### 🛠️ Implementation & Usage

7. **[Implementation Guide](Implementation-Guide.md)** - Configuration, providers, and advanced usage  
8. **[API Reference](API-Reference.md)** - Complete class and method documentation

### 🚀 Operations (As Needed)

9. **[Migration Guide](Migration-Guide.md)** - Upgrading existing fields _(coming soon)_
10. **[Key Management](Key-Management.md)** - Rotation and best practices _(coming soon)_

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
  parsed = URI.parse(uri)
  pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"
  
  @pools[pool_key] ||= ConnectionPool.new(size: 10) do
    Redis.new(host: parsed.host, port: parsed.port, db: parsed.db || 0)
  end
  
  @pools[pool_key].with { |conn| conn }
end
```

### Object Relationships (RelatableObjects)
```ruby
class Customer < Familia::Horreum
  feature :relatable_object
  self.logical_database = 0
  field :name, :email
end

class Domain < Familia::Horreum  
  feature :relatable_object
  self.logical_database = 0
  field :name, :dns_zone
end

# Create objects with automatic ID generation
customer = Customer.new(name: "Acme Corp")
domain = Domain.new(name: "acme.com")

# Establish ownership
Customer.owners.set(domain.objid, customer.objid)
domain.owner?(customer)  # => true
```


## Related Resources

- [Familia README](https://github.com/delano/familia) - Main project documentation
- [Issue #57](https://github.com/delano/familia/issues/57) - Original feature proposal
- [Issue #58](https://github.com/delano/familia/issues/58) - Wiki documentation tracking
