
# Familia - Overview

> [!NOTE]
> This document refers to Valkey throughout, but all examples and patterns work identically with Valkey/Redis. Familia supports both Valkey and Valkey/Redis as they share the same protocol and data structures.

## Introduction

Familia is a Ruby ORM for Valkey (Redis) that provides object-oriented access to Valkey's native data structures. Unlike traditional ORMs that map objects to relational tables, Familia preserves Valkey's performance and flexibility while offering a familiar Ruby interface.

**Why Familia?**
- Maps Ruby objects directly to Valkey's native data structures (strings, lists, sets, etc.)
- Maintains Valkey's atomic operations and performance characteristics
- Handles complex patterns (quantization, encryption, expiration, relationships) out of the box
- Modular feature system for organizing functionality across complex projects

## Core Concepts

### What is a Horreum Class?

The `Horreum` class is Familia's foundation, representing Valkey-compatible objects. It's named after ancient Roman storehouses, reflecting its purpose as a structured data repository.

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

  # JSON string fields (type-preserving storage)
  json_string :last_synced_at, default: 0.0
  # Usage: last_synced_at stores Float, retrieves Float (not String)

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

### DataType Naming Options

Familia provides both traditional concise names and explicit names for DataType methods to avoid namespace confusion with Ruby core types:

```ruby
class Product < Familia::Horreum
  # Traditional naming (concise, safe for lowercase)
  string :view_count     # Creates StringKey instance
  list :categories       # Creates ListKey instance

  # Explicit naming (clear intent, namespace-safe)
  stringkey :description # Creates StringKey instance
  listkey :history       # Creates ListKey instance

  # JSON string (type-preserving alternative to StringKey)
  json_string :metadata  # Creates JsonStringKey instance
  json_stringkey :config # Creates JsonStringKey instance

  # Both work identically - choose based on preference
  set :tags              # UnsortedSet (unchanged)
  sorted_set :ratings    # SortedSet (unchanged)
  hashkey :attributes    # HashKey (unchanged)
end

# Access patterns are identical
product.view_count.class        # => Familia::StringKey
product.description.class       # => Familia::StringKey
product.metadata.class          # => Familia::JsonStringKey
product.categories.class        # => Familia::ListKey
product.history.class           # => Familia::ListKey
```

**Key Benefits:**
- **Developer Choice**: Use concise (`string`, `list`) or explicit (`stringkey`, `listkey`) method names
- **Namespace Safety**: No confusion with Ruby's core `String`, `Array`, `Set`, `Hash` types
- **Backward Compatibility**: All existing code continues to work unchanged
- **Future-Proof**: Clear naming convention for any new DataTypes

### Generated Method Patterns

Familia automatically generates methods for all field and data type declarations:

```ruby
class Product < Familia::Horreum
  # Field declarations generate three methods each
  field :name, :price
  # → name, name=, name!        # getter, setter, fast writer
  # → price, price=, price!     # getter, setter, fast writer

  # Data type declarations generate accessor, setter, and type check
  set :tags
  list :categories              # Traditional method
  listkey :search_history       # Explicit method (same functionality)
  hashkey :attributes
  # → tags, tags=, tags?        # accessor, setter, type check
  # → categories, categories=, categories?
  # → search_history, search_history=, search_history?
  # → attributes, attributes=, attributes?

  # Class-level data types
  class_set :global_tags
  class_counter :total_products
  # → Product.global_tags, Product.global_tags?
  # → Product.total_products, Product.total_products?
end

# Field method usage
product.name = "Ruby Gem"      # Set field value
product.name                   # Get field value
product.name!("New Name")      # Set and save immediately

# Data type method usage
product.tags                   # Get UnsortedSet instance
product.tags = new_set         # Replace UnsortedSet instance
product.tags?                  # => true (confirms it's an UnsortedSet)

# Method conflict resolution
field :type, on_conflict: :skip      # Skip if method exists
field :id, on_conflict: :overwrite   # Force overwrite existing method
```

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
# => {id: "123", email: "alice@example.com", full_name: "Alice Windows"}
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

**Key Benefits:**
- **Time Bucketing**: Group time-based data into configurable intervals (minutes, hours, days)
- **Reduced Storage**: Aggregate similar data points to optimize memory usage
- **Analytics Ready**: Perfect for dashboards and time-series data visualization

> For advanced quantization strategies, value bucketing, geographic quantization, and performance patterns, see the [Technical Reference](reference/api-technical.md#quantization-feature-v200-pre7).

### Object Identifiers

Automatically generate unique identifiers for objects:

```ruby
class Document < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4
  field :title
  field :content
end

class Session < Familia::Horreum
  feature :object_identifier, generator: :hex
  field :user_id
  field :data
end

# Objects get automatic IDs
doc = Document.create(title: "My Doc")
doc.objid  # => "550e8400-e29b-41d4-a716-446655440000" (UUID)

session = Session.create(user_id: "123")
session.objid  # => "a1b2c3d4e5f6" (hex)
```

**Available Generators:**
- `:uuid_v4` - Standard UUID format for global uniqueness
- `:hex` - Compact hexadecimal identifiers for internal use

> For custom generators, collision detection, and advanced identifier patterns, see the [Technical Reference](reference/api-technical.md#object-identifier-feature-v200-pre7).

### Specialized Field Types

Familia provides specialized field types beyond basic fields:

```ruby
class SecureModel < Familia::Horreum
  feature :encrypted_fields
  feature :transient_fields
  feature :object_identifier

  # Regular fields generate: name, name=, name!
  field :name, :email

  # Encrypted fields return ConcealedString instances
  encrypted_field :api_key, :credit_card
  # → api_key, api_key=, api_key!
  # → Values wrapped in ConcealedString for safety

  # Transient fields never persist to database
  transient_field :password, :session_token
  # → password, password= (no fast writer method)
  # → Values wrapped in RedactedString

  # Note: All transient field values are automatically wrapped in RedactedString
  # for security - they never persist to the database

  # Object identifier fields auto-generate unique IDs when using the feature
  # → objid, objid= (lazy generation, preserves initialization values)
end

# Usage examples
model = SecureModel.create(name: "Alice", api_key: "secret123")

# Encrypted field safety
model.api_key.class                      # => ConcealedString
model.api_key.to_s                       # => "[CONCEALED]" (safe for logs)
model.api_key.reveal                     # => "secret123" (actual value)

# Transient field behavior
model.password = "temp123"
model.save
model.reload
model.password                           # => nil (not persisted)

# Object identifier generation
model.objid                              # => Auto-generated UUID or hex
model.objid_generator_used               # => :uuid_v7 (provenance)
```

**Field Type Features:**
- **Method Conflict Resolution**: Use `on_conflict: :skip/:warn/:overwrite` for existing methods
- **Fast Writer Control**: Use `fast_method: false` to disable fast writers
- **Custom Method Names**: Use `as: :custom_name` for different method names
- **Security by Default**: Encrypted and transient fields prevent accidental exposure

### External Identifiers

Integrate with external systems and validate identifiers:

```ruby
class ExternalUser < Familia::Horreum
  feature :external_identifier

  field :external_id
  field :name
  field :sync_status

  # Validate external system identifiers
  def valid_external_id?
    external_id.present? && external_id.match?(/^ext_\d+$/)
  end
end

# Map external identifiers to internal objects
user = ExternalUser.create(external_id: "ext_12345", name: "Alice")
```

This feature helps maintain consistency when integrating with external APIs or legacy systems.

> For advanced external identifier patterns, batch operations, and sync status management, see the [Technical Reference](reference/api-technical.md#external-identifier-feature-v200-pre7).

### Relationships

Manage complex object relationships with CRUD operations:

```ruby

# Define relationships
class User < Familia::Horreum
  feature :relationships
  identifier_field :email
  field :email, :name

  participates_in Team, :teams
end

class Team < Familia::Horreum
  feature :relationships
  identifier_field :name
  field :name, :description
end

# Create relationships
alice = User.create(email: "alice@example.com", name: "Alice")
dev_team = Team.create(name: "developers", description: "Dev Team")

# Add relationships
alice.teams << dev_team

# Query relationships
alice.teams.to_a         # => [dev_team identifiers]
dev_team.in_user_teams?(alice)  # => true

# Remove relationships
alice.teams.delete(dev_team.identifier)

# Bulk operations
alice.teams.merge([qa_team.identifier, design_team.identifier])
alice.teams.clear
```

#### Generated Relationship Method Patterns

The relationships feature automatically generates comprehensive method patterns:

```ruby
# Participation methods (on User class)
alice.in_team_teams?(dev_team)           # Check membership
alice.add_to_team_teams(dev_team, 1.0)   # Add with score
alice.remove_from_team_teams(dev_team)   # Remove membership
alice.score_in_team_teams(dev_team)      # Get participation score

# Target class methods (on Team class)
dev_team.teams                           # Collection getter (SortedSet)
dev_team.add_team(alice, 1.0)            # Add single member with score
dev_team.remove_team(alice)              # Remove single member
dev_team.add_teams([alice, bob])         # Bulk add members

# Indexing methods (if using indexed_by)
class User < Familia::Horreum
  indexed_by :email, :email_index, target: Team
end

# Generated index methods on User:
alice.add_to_team_email_index(dev_team)        # Add to index
alice.remove_from_team_email_index(dev_team)   # Remove from index
alice.update_in_team_email_index(dev_team, old_email)  # Update index

# Generated finder methods on Team:
Team.find_by_email("alice@example.com")        # Find user by email
Team.find_all_by_email(["alice@example.com"])  # Bulk find by emails
Team.email_index_for("alice@example.com")      # Direct index access
```

**Key Features:**
- **Bidirectional Links**: Automatic reverse relationship management
- **Ruby-like Syntax**: Clean `customer.domains << domain` collection operations
- **Automatic Indexing**: Efficient O(1) lookups with automatic index maintenance
- **Performance Optimized**: Bulk operations and efficient sorted set operations

> For advanced relationship patterns, permission-encoded relationships, time-series tracking, and performance optimization, see the [Technical Reference](reference/api-technical.md#relationships-feature-v200-pre7).

### Transient Fields

Handle temporary or sensitive data that shouldn't persist:

```ruby
class LoginAttempt < Familia::Horreum
  feature :transient_fields

  field :username
  field :timestamp
  transient_field :password
  redacted_field :security_token
end

attempt = LoginAttempt.new(
  username: "alice",
  password: "secret123",
  security_token: "sensitive_data"
)

# Transient fields aren't saved to Valkey
attempt.save
attempt.reload
attempt.password        # => nil (not persisted)

# Redacted fields return safe values
attempt.security_token.class    # => RedactedString
attempt.security_token.to_s     # => "[REDACTED]"
attempt.security_token.reveal   # => "sensitive_data"
```

**Field Types:**
- **Transient Fields**: Exist only in memory, never persisted
- **Redacted Fields**: Return `[REDACTED]` when converted to strings for logging safety

> For RedactedString implementation details, single-use patterns, and security considerations, see the [Technical Reference](reference/api-technical.md#transient-fields-feature-v200-pre5).

### Permission Management

The relationships feature includes a powerful permission management system:

```ruby
class Document < Familia::Horreum
  feature :relationships
  permission_tracking :user_permissions

  field :title, :content
end

# Generated permission control methods
doc.grant(user, :read, :write)           # Grant permissions to user
doc.revoke(user, :write)                 # Revoke specific permissions
doc.add_permission(user, :delete)        # Add to existing permissions
doc.set_permissions(user, :read, :edit)  # Replace all permissions

# Generated permission query methods
doc.can?(user, :read)                    # Check if user has permission
doc.permissions_for(user)                # Get user's permission array
doc.category?(user, :content_editor)     # Check permission category
doc.permission_tier_for(user)            # Get tier: :administrator, :content_editor, :viewer, :none

# Generated bulk operations
doc.all_permissions                      # Hash of all users and permissions
doc.clear_all_permissions               # Remove all permissions
doc.users_by_category(:viewer)          # Filter users by permission level

# Generated collection filtering
doc.accessible_items("org:123:documents")               # Get items with scores
doc.items_by_permission("org:123:documents", :readable) # Filter by permission
doc.permission_matrix("org:123:documents")              # Count by permission level
doc.admin_access?(user, "org:123:documents")            # Check admin privileges
```

**Permission Categories:**
- `:viewer` - Read-only access
- `:content_editor` - Read and edit access
- `:administrator` - Full access including user management

**Key Features:**
- **Granular Control**: Fine-grained permission assignment per user
- **Category-based Queries**: Efficient filtering by permission levels
- **Bulk Operations**: Manage permissions across collections
- **Performance Optimized**: O(1) permission checks using Valkey/Redis sorted sets

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
  conn.zadd("active_users", Familia.now.to_i, user.id)
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

Protect sensitive data at rest with transparent encryption:

```ruby
# First, configure encryption keys
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY'],
    v2: ENV['FAMILIA_ENCRYPTION_KEY_V2']
  }
  config.current_key_version = :v2
  config.encryption_personalization = 'MyApp-2024'  # Optional
end

# Validate configuration before use
Familia::Encryption.validate_configuration!

class SecureUser < Familia::Horreum
  feature :encrypted_fields

  identifier_field :id
  field :id, :email               # Plaintext fields
  encrypted_field :ssn            # Encrypted with field-specific key
  encrypted_field :credit_card    # Another encrypted field
  encrypted_field :notes, aad_fields: [:id, :email]  # With tamper protection
end

# Usage is transparent
user = SecureUser.new(
  id: 'user123',
  email: 'alice@example.com',
  ssn: '123-45-6789',
  credit_card: '4111-1111-1111-1111',
  notes: 'VIP customer'
)
user.save

# Access returns ConcealedString to help prevent accidentally logging or displaying the value
user.ssn.class                  # => ConcealedString
user.ssn.reveal                 # => "123-45-6789" (actual value)
user.ssn.to_s                   # => "[CONCEALED]" (safe for logging)

# Performance optimization for multiple operations
Familia::Encryption.with_request_cache do
  user.ssn = "new-ssn"
  user.credit_card = "new-card"
  user.save  # Reuses derived keys
end

# Key rotation support
user.re_encrypt_fields!  # Re-encrypt with current key version
user.encrypted_fields_status  # Check encryption status
```

**Key Features:**
- **Transparent Encryption**: Fields encrypted/decrypted automatically
- **Security by Default**: ConcealedString prevents accidental value exposure
- **Key Rotation**: Seamless updates with backward compatibility
- **Multiple Algorithms**: XChaCha20-Poly1305 (preferred) with AES-256-GCM fallback

> For advanced encryption configuration, multiple providers, request caching, and key rotation procedures, see the [Technical Reference](reference/api-technical.md#encrypted-fields-feature-v200-pre5).

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

### Feature System Architecture

Familia's modular feature system helps organize functionality across complex projects:

```ruby
class ComplexModel < Familia::Horreum
  # Enable features as needed
  feature :expiration           # TTL management
  feature :safe_dump           # API-safe serialization
  feature :relationships       # Object relationships
  feature :encrypted_fields    # Secure field storage
end
```

**Key Benefits:**
- **Per-Class Configuration**: Each model can configure features independently
- **Automatic Loading**: Use autoloader for large projects to organize features in separate files
- **Dependency Management**: Features can depend on other features for complex functionality
- **Reusable Modules**: Share common functionality across multiple models

> For advanced feature organization patterns, autoloader configuration, and complex dependency management, see the [Technical Reference](reference/api-technical.md#advanced-feature-system-architecture).

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

### Production Configuration

**Environment-based Setup:**
```ruby
# config/familia.rb
case ENV['RAILS_ENV'] || ENV['RACK_ENV']
when 'production'
  Familia.redis_config = {
    host: ENV['REDIS_HOST'],
    port: ENV['REDIS_PORT'],
    password: ENV['REDIS_PASSWORD'],
    ssl: true,
    timeout: 10,
    reconnect_attempts: 3
  }
when 'development'
  Familia.uri = 'redis://localhost:6379/0'
when 'test'
  Familia.uri = 'redis://localhost:2525/3'
end
```

**Advanced Connection Pooling:**
```ruby
# Multi-database with connection pooling
require 'connection_pool'

primary_pool = ConnectionPool.new(size: 20) { Redis.new(url: ENV['PRIMARY_REDIS_URL']) }
cache_pool = ConnectionPool.new(size: 10) { Redis.new(url: ENV['CACHE_REDIS_URL']) }

Familia.connection_provider = lambda do |uri|
  case uri
  when /primary/
    primary_pool.with { |conn| yield conn }
  when /cache/
    cache_pool.with { |conn| yield conn }
  else
    Redis.new(url: uri)
  end
end
```

### Encryption Setup

**Development Keys:**
```ruby
# Generate base64-encoded 32-byte keys
Familia.configure do |config|
  config.encryption_keys = {
    v1: Base64.strict_encode64(SecureRandom.bytes(32)),
    v2: Base64.strict_encode64(SecureRandom.bytes(32))
  }
  config.current_key_version = :v2
  config.encryption_personalization = "#{Rails.application.class.name}-#{Rails.env}"
end
```

**Production Security:**
```ruby
# Use secure key management
Familia.configure do |config|
  # Load keys from secure key management service
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY_V1'],
    v2: ENV['FAMILIA_ENCRYPTION_KEY_V2'],
    v3: ENV['FAMILIA_ENCRYPTION_KEY_V3']  # For rotation
  }
  config.current_key_version = :v3
  config.encryption_personalization = ENV['FAMILIA_ENCRYPTION_CONTEXT']

  # Validate configuration on startup
  Familia::Encryption.validate_configuration!
end
```

> For production configuration patterns, advanced connection pooling, multi-database setup, and environment-based configuration, see the [Technical Reference](reference/api-technical.md#connection-management-v200-pre).

## Common Patterns

### Bulk Operations

```ruby
# Load multiple objects
users = User.multiget('alice@example.com', 'bob@example.com')

# Batch operations
User.transaction do |conn|
  conn.set('user:alice:status', 'active')
  conn.zadd('active_users', Familia.now.to_i, 'alice')
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
puts user.dbkey  # Shows the Valkey key that would be used
```

**Encryption Issues:**
```ruby
# Validate encryption config
Familia::Encryption.validate_configuration!

# Check encryption status for specific fields
user.encrypted_fields_status
# => {ssn: {encrypted: true, key_version: :v2}, credit_card: {encrypted: false}}

# Re-encrypt all fields with current key
user.re_encrypt_fields!
```

**Relationship Issues:**
```ruby
# Debug relationship indexes
alice.relationships_debug_info
# => Shows internal relationship state and indexes

# Check relationship consistency
User.validate_relationship_indexes!  # Raises if inconsistent
```

**Feature Conflicts:**
```ruby
# Check which features are enabled
MyModel.features_enabled
# => [:safe_dump, :encrypted_fields, :relationships]

# Check feature dependencies
MyModel.feature_dependencies(:relationships)
# => Shows required features

# Verify feature loading order
Familia.debug = true  # Shows feature loading sequence
```

### Debug Mode

```ruby
# Enable debug logging
Familia.debug = true

# Check what's in Valkey
Familia.dbclient.keys('*')  # List all keys (use carefully in production)
```

## Testing

### Test Configuration

```ruby
# test_helper.rb or spec_helper.rb
require 'familia'

# Use separate test database
Familia.uri = 'redis://localhost:2525/3'

# Setup encryption for tests
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clear data between tests
def clear_redis
  Familia.dbclient.flushdb
end

# Feature-specific testing patterns
def setup_encryption_for_tests
  test_keys = {
    v1: Base64.strict_encode64('a' * 32),
    v2: Base64.strict_encode64('b' * 32)
  }
  Familia.configure do |config|
    config.encryption_keys = test_keys
    config.current_key_version = :v1
    config.encryption_personalization = 'TestApp-Test'
  end
end

def test_relationships_cleanup
  # Clean up relationship indexes
  Familia.dbclient.keys('*:relationships:*').each do |key|
    Familia.dbclient.del(key)
  end
end
```

### Feature Testing Strategies

**Testing with Encrypted Fields:**
```ruby
# test/models/secure_user_test.rb
require 'test_helper'

class SecureUserTest < Minitest::Test
  def setup
    setup_encryption_for_tests
    clear_redis
  end

  def test_encrypted_field_concealment
    user = SecureUser.create(
      id: 'test123',
      email: 'test@example.com',
      ssn: '123-45-6789'
    )

    assert_instance_of Familia::Features::EncryptedFields::ConcealedString, user.ssn
    assert_equal '[CONCEALED]', user.ssn.to_s
    assert_equal '123-45-6789', user.ssn.reveal
  end
end
```

**Testing Relationships:**
```ruby
def test_relationship_bidirectionality
  alice = User.create(email: "alice@test.com")
  team = Team.create(name: "test-team")

  alice.add_membership(team)

  assert_includes alice.memberships, team
  assert_includes team.members, alice
end
```

**Testing Transient Fields:**
```ruby
def test_transient_field_not_persisted
  attempt = LoginAttempt.new(
    username: "alice",
    password: "secret"
  )
  attempt.save

  reloaded = LoginAttempt.load(attempt.identifier)
  assert_nil reloaded.password  # Not persisted
  assert_equal "alice", reloaded.username  # Regular field persisted
end
```

> For comprehensive testing patterns, advanced test helpers, and feature-specific testing strategies, see the [Technical Reference](reference/api-technical.md#testing-patterns).
