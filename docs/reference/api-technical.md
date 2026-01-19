# Familia v2.0.0-pre Series Technical Reference

**Familia** is a Ruby ORM for Valkey/Redis providing object mapping, relationships, and advanced features like encryption, connection pooling, and permission systems. This technical reference covers the major classes, methods, and usage patterns introduced in the v2.0.0-pre series.

> For conceptual understanding and getting started with Familia, see the [Overview Guide](../overview.md). This document provides detailed implementation patterns and advanced configuration options.

---

## Core Architecture

### Base Classes

#### `Familia::Horreum` - Primary ORM Base Class
The main base class for Valkey/Redis-backed objects, similar to ActiveRecord models.

```ruby
class User < Familia::Horreum
  # Basic field definitions
  field :name, :email, :created_at

  # Valkey/Redis data types as instance variables
  list :sessions      # Valkey/Redis list
  set :tags          # Valkey/Redis set
  zset :scores       # Valkey/Redis sorted set
  hashkey :settings  # Valkey/Redis hash
end
```

**Key Methods:**
- `save` - Persist object to Valkey/Redis
- `save_if_not_exists` - Conditional persistence, returns false if exists
- `save_if_not_exists!` - Conditional persistence, raises RecordExistsError if exists
- `load` - Load object from Valkey/Redis
- `exists?` - Check if object exists in Valkey/Redis
- `destroy` - Remove object from Valkey/Redis

#### `Familia::DataType` - Valkey/Redis Data Type Wrapper
Base class for Valkey/Redis data type implementations.

**Registered Types:**
- `String` - Valkey/Redis strings
- `List` - Valkey/Redis lists
- `Set` - Valkey/Redis sets
- `SortedSet` - Valkey/Redis sorted sets
- `HashKey` - Valkey/Redis hashes
- `Counter` - Atomic counters
- `Lock` - Distributed locks

---

## Feature System

### Feature Architecture
Modular system for extending Horreum classes with reusable functionality.

```ruby
class Customer < Familia::Horreum
  feature :expiration      # TTL management
  feature :safe_dump       # API-safe serialization
  feature :encrypted_fields # Field encryption
  feature :transient_fields # Non-persistent fields
  feature :relationships   # Object relationships

  field :name, :email
  encrypted_field :api_key
  transient_field :password
end
```

### Built-in Features

#### 1. Expiration Feature
TTL (Time To Live) management with cascading expiration.

```ruby
class Session < Familia::Horreum
  feature :expiration

  field :user_id, :token
  default_expiration 24.hours

  # Cascade expiration to related objects
  cascade_expiration_to :user_activity
end

session = Session.new(user_id: 123, token: "abc123")
session.save
session.expire_in(1.hour)  # UnsortedSet custom expiration
session.ttl                # Check remaining time
```

#### 2. SafeDump Feature
API-safe serialization excluding sensitive fields.

```ruby
class User < Familia::Horreum
  feature :safe_dump

  field :name, :email, :password_hash
  safe_dump_field :name, :email  # Only these fields in safe_dump
end

user = User.new(name: "Alice", email: "alice@example.com", password_hash: "secret")
user.safe_dump  # => {"name" => "Alice", "email" => "alice@example.com"}
```

#### 3. Encrypted Fields Feature
Transparent field-level encryption with multiple providers.

```ruby
# Configuration
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY'],
    v2: ENV['FAMILIA_ENCRYPTION_KEY_V2']
  }
  config.current_key_version = :v2
end

class Vault < Familia::Horreum
  feature :encrypted_fields

  field :name                    # Plaintext
  encrypted_field :secret_key    # Encrypted with XChaCha20-Poly1305
  encrypted_field :api_token     # Field-specific key derivation
  encrypted_field :private_data  # Transparent access
end

vault = Vault.new(
  name: "Production Secrets",
  secret_key: "super-secret-123",
  api_token: "sk-1234567890"
)
vault.save

# Transparent access - automatically encrypted/decrypted
vault.secret_key  # => "super-secret-123" (decrypted on access)
```

**Encryption Providers:**
- **XChaCha20-Poly1305** (preferred) - Requires `rbnacl` gem
- **AES-256-GCM** (fallback) - Uses OpenSSL, no dependencies

**Advanced Security Implementation:**
```ruby
# Multiple encryption providers with fallback
class CriticalData < Familia::Horreum
  feature :encrypted_fields

  encrypted_field :credit_card
  encrypted_field :ssn
  encrypted_field :notes
end

# Key versioning and rotation
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['OLD_KEY'],      # Legacy key
    v2: ENV['CURRENT_KEY'],  # Current key
    v3: ENV['NEW_KEY']       # New key for rotation
  }
  config.current_key_version = :v2
  config.encryption_personalization = 'MyApp-2024'  # Optional (XChaCha20 only)
end

# Operations with encrypted fields
record = CriticalData.new(
  credit_card: "4111-1111-1111-1234",
  ssn: "123-45-6789",
  notes: "Customer notes"
)
record.save

# Verify encryption status
puts "Record #{record.identifier}: #{status}"
# => {credit_card: {encrypted: true, algorithm: "xchacha20poly1305", cleared: false}}
```

**ConcealedString Security Features:**
```ruby
# Automatic protection against accidental exposure
user = CriticalData.load("user123")

# Safe operations
user.credit_card.class           # => ConcealedString
user.credit_card.to_s           # => "[CONCEALED]"
user.credit_card.inspect        # => "[CONCEALED]"
user.credit_card.to_json        # => "\"[CONCEALED]\""

# Explicit access when needed
actual_card = user.credit_card.reveal  # => "4111-1111-1111-1234"

# Logging safety
Rails.logger.info "Processing card: #{user.credit_card}"
# => "Processing card: [CONCEALED]" (safe for logs)

# JSON serialization safety
user_data = user.to_json
# All encrypted fields show as "[CONCEALED]" in JSON
```

#### 4. Transient Fields Feature
Non-persistent fields with memory-safe handling.

```ruby
class LoginForm < Familia::Horreum
  feature :transient_fields

  field :username              # Persistent
  transient_field :password    # Never stored in Redis
  transient_field :csrf_token  # Runtime only
end

form = LoginForm.new(username: "alice", password: "secret123")
form.save  # Only saves 'username', password is transient

form.password.class  # => Familia::Features::TransientFields::RedactedString
form.password.to_s   # => "[REDACTED]" (safe for logging)
form.password.reveal # => "secret123" (explicit access)
```

**RedactedString** - Security wrapper preventing accidental exposure:
- `to_s` returns "[REDACTED]"
- `inspect` returns "[REDACTED]"
- `reveal` method for explicit access
- Safe for logging and serialization

#### 5. Relationships Feature
Comprehensive object relationship system with automatic management, clean Ruby-idiomatic syntax, and simplified method generation.

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email

  # Collections for storing related object IDs
  set :domains           # Simple set
  zset :activity   # Scored/sorted collection

  # Class-level indexed lookups (automatically managed on save/destroy)
  class_indexed_by :email, :email_lookup

  # Class-level tracking with scoring (automatically managed on save/destroy)
  class_participates_in :all_customers, score: :created_at
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name, :status

  # Bidirectional membership with clean << operator support
  participates_in Customer, :domains

  # Relationship-scoped indexing (per-customer domain lookups)
  indexed_by :name, :domain_index, target: Customer

  # Class-level conditional tracking with lambda scoring
  class_participates_in :active_domains,
                   score: -> { status == 'active' ? Familia.now.to_i : 0 }
end
```

**Relationship Operations with Automatic Management:**

```ruby
# Create and save objects (automatic indexing and tracking)
customer = Customer.new(custid: "cust123", name: "Acme Corp", email: "admin@acme.com")
customer.save  # Automatically adds to email_lookup and all_customers

domain = Domain.new(domain_id: "dom456", name: "acme.com", status: "active")
domain.save    # Automatically adds to active_domains

# Establish relationships using clean Ruby-like << operator
customer.domains << domain  # Clean, Ruby-idiomatic collection syntax

# Query relationships
domain.in_customer_domains?(customer.custid)  # => true
customer.domains.member?(domain.identifier)   # => true

# O(1) indexed lookups (automatic management - no manual calls needed)
found_id = Customer.email_lookup.get("admin@acme.com")
found_customer = Customer.find_by_email("admin@acme.com")  # Convenience method

# Relationship-scoped lookups
customer_domain = customer.find_by_name("acme.com")  # Find within customer

# Class-level tracking queries
recent_customers = Customer.all_customers.range_by_score(
  (Familia.now - 24.hours).to_i, '+inf'
)
active_domains = Domain.active_domains.members
```

**Key Features:**
- **Automatic Management**: Objects automatically added/removed from class-level collections on save/destroy
- **Clean Syntax**: Collections support Ruby-like `customer.domains << domain` syntax
- **Simplified Methods**: No complex "global" terminology - uses clear `class_` prefixes
- **Performance**: O(1) hash lookups and efficient sorted set operations
- **Flexibility**: Supports class-level and relationship-scoped indexing patterns

#### 6. Object Identifier Feature
Automatic generation of unique object identifiers with configurable strategies.

Default generator is `:uuid_v7` (UUID version 7 with embedded timestamp).

```ruby
class Document < Familia::Horreum
  feature :object_identifier  # Uses default :uuid_v7

  field :title, :content, :created_at
end

class Session < Familia::Horreum
  feature :object_identifier, generator: :hex, length: 16

  field :user_id, :data, :expires_at
end

class ApiKey < Familia::Horreum
  feature :object_identifier, generator: :custom

  field :name, :permissions, :created_at

  # Custom generator implementation
  def self.generate_identifier
    "ak_#{SecureRandom.alphanumeric(32)}"
  end
end
```

**Generator Types:**
- `:uuid_v7` - UUID version 7 with embedded timestamp (default, 36 characters)
- `:uuid_v4` - Standard UUID v4 format (36 characters)
- `:hex` - High-entropy hexadecimal strings (256-bit via SecureIdentifier)
- Proc/Lambda - Custom generation logic provided as a callable

**Technical Implementation:**
```ruby
# Auto-generated on object creation
doc = Document.create(title: "My Document")
doc.objid  # => "01234567-89ab-7def-8000-123456789abc"  # UUID v7 format

session = Session.create(user_id: "123")
session.objid  # => "a1b2c3d4e5f67890"

# Custom identifier with proc
api_key = ApiKey.create(name: "Production API")
api_key.objid  # => "ak_Xy9ZaBcD3fG8HjKlMnOpQrStUvWxYz12"

# Feature options per-class isolation
Document.feature_options(:object_identifier)
#=> {generator: :uuid_v7}
```

#### 7. External Identifier Feature
Derives deterministic external identifiers from object identifiers.

```ruby
class ExternalUser < Familia::Horreum
  feature :external_identifier

  identifier_field :id
  field :id, :name

  # External ID is automatically derived from objid
  # Format: 'ext_' + base36(truncated_hash(objid))
end

class APIKey < Familia::Horreum
  feature :external_identifier, format: 'api-%{id}'

  field :name, :permissions
end
```

**External ID Management:**
```ruby
# External ID is deterministically derived from objid
user = ExternalUser.new(name: "John Doe")
user.save
user.objid  # => "01234567-89ab-7def-8000-123456789abc"
user.extid  # => "ext_abc123def456ghi789"  # Deterministic from objid

# Same objid always produces same extid
user2 = ExternalUser.new(objid: user.objid, name: "John Doe")
user2.extid  # => "ext_abc123def456ghi789"  # Identical

# Custom format with APIKey
key = APIKey.new(name: "Production")
key.extid  # => "api-xyz789abc123"
```

#### 8. Quantization Feature
Time-based data bucketing for analytics and caching.

```ruby
class DailyMetric < Familia::Horreum
  feature :quantization

  identifier_field :metric_key
  field :metric_key, :bucket_timestamp, :value_count, :sum_value

  # Example: Basic time quantization
  string :counter, default_expiration: 1.day, quantize: [10.minutes, '%H:%M']
end
```

**Basic Usage:**
```ruby
# Create metric with quantized timestamp
metric = DailyMetric.new(metric_key: "page_views")
metric.counter.increment

# Time-based data grouping occurs automatically
# All data within the same 10-minute window shares the same key
```

**Key Benefits:**
- **Time Bucketing**: Group time-based data into configurable intervals
- **Reduced Storage**: Aggregate similar data points to optimize memory usage
- **Analytics Ready**: Perfect for dashboards and time-series data visualization

---

## Advanced Feature System Architecture

### Feature Autoloader for Project Organization
Automatically load features from directory structure.

```ruby
# app/models/customer.rb - Main model file
class Customer < Familia::Horreum
  include Familia::Features::Autoloader
  # Automatically loads all .rb files from app/models/customer/*.rb

  # Core model definition
  identifier_field :custid
  field :custid, :name, :email, :created_at
end

# app/models/customer/notifications.rb
class Customer < Familia::Horreum
  def send_welcome_email
    NotificationService.send_template(
      email: email,
      template: 'customer_welcome',
      variables: { name: name, custid: custid }
    )
  end

  def send_invoice_reminder(invoice_id)
    NotificationService.send_template(
      email: email,
      template: 'invoice_reminder',
      variables: { invoice_id: invoice_id }
    )
  end
end

# app/models/customer/analytics.rb
class Customer < Familia::Horreum
  # Analytics methods added to Customer
  def track_activity(activity_type, metadata = {})
    activity_data = {
      custid: custid,
      activity: activity_type,
      timestamp: Familia.now.to_i,
      metadata: metadata
    }

    # Store in customer's activity stream
    activities.unshift(activity_data.to_json)
    activities.trim(0, 999)  # Keep last 1000 activities
  end

  def recent_activities(limit = 10)
    activities.range(0, limit - 1).map { |json| JSON.parse(json) }
  end
end
```

### Feature Dependencies
Features can declare dependencies that are automatically resolved.

```ruby
# External identifier depends on object_identifier
class User < Familia::Horreum
  feature :external_identifier  # Automatically includes :object_identifier
  field :name
end

# Feature dependency resolution
Familia::Base.add_feature ExternalIdentifier, :external_identifier, depends_on: [:object_identifier]

# When external_identifier is included, object_identifier is automatically loaded first
end
```

### Per-Class Feature Registration

Register custom features for specific model classes with ancestry chain lookup.

```ruby
# Define a custom feature module
module CustomerAnalytics
  def track_purchase(amount)
    purchases.increment(amount)
  end
end

# Register feature only for Customer and its subclasses
Customer.add_feature CustomerAnalytics, :customer_analytics

class Customer < Familia::Horreum
  feature :customer_analytics  # Available via Customer's registry
end

class PremiumCustomer < Customer
  feature :customer_analytics  # Inherited via ancestry chain
end

class Session < Familia::Horreum
  # feature :customer_analytics  # Not available - would raise error
end
```

**Benefits:**
- Features can have the same name across different model hierarchies
- Natural inheritance through Ruby's class hierarchy
- Better namespace management for large applications

### Per-Class Feature Configuration Isolation
Each class maintains independent feature options.

```ruby
class PrimaryCache < Familia::Horreum
  feature :expiration
  feature :object_identifier, generator: :uuid_v7

  field :cache_key, :value, :hit_count
  default_expiration 24.hours
end

class SecondaryCache < Familia::Horreum
  feature :expiration
  feature :object_identifier, generator: :hex  # Different generator

  field :cache_key, :backup_value, :backup_timestamp
  default_expiration 7.days
end

# Feature options are completely isolated
PrimaryCache.feature_options(:object_identifier)
#=> {generator: :uuid_v7}

SecondaryCache.feature_options(:object_identifier)
#=> {generator: :hex}
```

### Runtime Feature Checking
Check which features are enabled on a class.

```ruby
class SecureModel < Familia::Horreum
  feature :expiration
  feature :encrypted_fields
  feature :safe_dump

  field :name, :status
  encrypted_field :api_key
  safe_dump_field :name
end

# Check enabled features
SecureModel.features_enabled
#=> [:expiration, :encrypted_fields, :safe_dump]

# Check feature options
SecureModel.feature_options(:encrypted_fields)
#=> {} # Default options

# Each class tracks its own features
class BasicModel < Familia::Horreum
  feature :expiration
  field :name
end

BasicModel.features_enabled
#=> [:expiration]
```

---

## Connection Management

### Connection Provider Pattern
Flexible connection pooling with provider-based architecture.

```ruby
# Basic Valkey/Redis connection
Familia.configure do |config|
  config.uri = "redis://localhost:6379/0"
end

# Custom connection provider with pooling
require 'connection_pool'

Familia.connection_provider = lambda do |uri|
  # Provider MUST return connection already on correct database
  parsed = URI.parse(uri)
  pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

  @pools ||= {}
  @pools[pool_key] ||= ConnectionPool.new(size: 10, timeout: 5) do
    Redis.new(
      host: parsed.host,
      port: parsed.port,
      db: parsed.db || 0
    )
  end

  @pools[pool_key].with { |conn| conn }
end
```

### Multi-Database Support
Configure different logical databases for different models.

```ruby
class User < Familia::Horreum
  logical_database 0  # Use database 0
  field :name, :email
end

class Session < Familia::Horreum
  logical_database 1  # Use database 1
  field :user_id, :token
end

class Cache < Familia::Horreum
  logical_database 2  # Use database 2
  field :key, :value
end
```

---

## Testing and Debugging

### Database Command Logging
Monitor all Redis commands with DatabaseLogger middleware.

```ruby
# Enable command logging (middleware registered automatically)
Familia.enable_database_logging = true

# Capture commands in tests
commands = DatabaseLogger.capture_commands do
  user = User.create(name: "Test User")
  user.save
end

puts commands.first.command  # => "SET user:123 {...}"
puts commands.first.μs       # => 567 (microseconds)

# Enable sampling for production
DatabaseLogger.sample_rate = 0.01  # Log 1% of commands

# Structured logging format
DatabaseLogger.structured_logging = true
# => "Redis command cmd=SET args=[key, value] duration_ms=0.42 db=0"
```

### Debug Mode
Enable comprehensive debugging output.

```ruby
# Via environment variable
ENV['FAMILIA_DEBUG'] = '1'
ENV['FAMILIA_TRACE'] = '1'

# Via configuration
Familia.configure do |config|
  config.debug = true
end

# Check database contents
Familia.dbclient.keys('user:*')

# Trace specific operations
Familia.trace :LOAD, redis_client, "user:123", "from cache"
```

### Connection Chain Debugging
Understand connection resolution order.

```ruby
# Connection resolution order:
# 1. Instance @dbclient if set
# 2. Class logical_database if configured
# 3. Connection provider if set
# 4. Global Familia connection

class DebugModel < Familia::Horreum
  logical_database 3
  field :name
end

model = DebugModel.new(name: "test")
# Uses database 3 from logical_database

model.dbclient = custom_connection
# Now uses custom_connection instead
```

## Performance Considerations

### Encryption Performance
- XChaCha20-Poly1305 is ~2x faster than AES-256-GCM
- Key derivation is NOT cached by default for security
- Use request-level caching for bulk operations:

```ruby
Familia::Encryption.with_request_cache do
  # Bulk operations with cached key derivation
  1000.times do |i|
    User.create(email: "user#{i}@example.com")
  end
end
```

### Connection Pooling
- Use connection_provider for multi-threaded environments
- Pool size should match thread count
- Connections are thread-safe when using provider pattern

### Feature Performance Impact
- **Encryption**: ~10-20% overhead for field access
- **Relationships**: O(1) for indexed lookups
- **Quantization**: Minimal overhead, improves storage efficiency
- **Safe Dump**: Lazy evaluation, only computed when called

---

## Migration Guide

### From Familia v1.x to v2.0
- Replace `redis_uri` with `uri` in configuration
- Update feature syntax from mixins to `feature` declarations
- Migrate from `global_` prefix to `class_` for class-level methods
- Update encryption configuration to new provider system

### Connection Provider Pattern
- Familia v2.0 uses redis-rb gem internally
- Connection providers must return Redis connections
- Uses RedisClient middleware architecture internally via redis-rb

---

## Summary

Familia v2.0.0-pre series provides a comprehensive ORM for Valkey/Redis with:
- **Modular Feature System**: Isolated, configurable features per class
- **Advanced Security**: Field-level encryption with multiple providers
- **Flexible Relationships**: Automatic management with clean Ruby syntax
- **Performance Optimized**: Connection pooling, sampling, and caching
- **Production Ready**: Debug logging, monitoring, and thread safety

For additional documentation and examples, see the [Familia GitHub repository](https://github.com/delano/familia).

class ActivityTracker < Familia::Horreum
  feature :relationships

  identifier_field :activity_id
  field :activity_id, :user_id, :activity_type, :data, :created_at

  # Class-level tracking with automatic management
  class_participates_in :user_activities, score: :created_at
  class_participates_in :activity_by_type,
                   score: -> { "#{activity_type}:#{created_at}".hash }
end

# Create and save activity (automatic tracking)
activity = ActivityTracker.new(
  activity_id: 'act123',
  user_id: 'user456',
  activity_type: 'login',
  created_at: Familia.now.to_i
)
activity.save  # Automatically added to both tracking collections

# Query recent activities (last hour)
hour_ago = (Familia.now - 1.hour).to_i
recent_activities = ActivityTracker.user_activities.range_by_score(
  hour_ago, '+inf'
)

# Get activities by type in time range
login_hash_start = "login:#{hour_ago}".hash
login_hash_end = "login:#{Familia.now.to_i}".hash
login_activities = ActivityTracker.activity_by_type.range_by_score(
  login_hash_start, login_hash_end
)
```

---

## Data Type Usage Patterns

### Advanced Sorted Set Operations
Leverage Valkey/Redis sorted sets for rankings, time series, and scored data.

```ruby
class Leaderboard < Familia::Horreum
  identifier_field :game_id
  field :game_id, :name
  sorted_set :scores
end

leaderboard = Leaderboard.new(game_id: "game1", name: "Daily Challenge")

# Add player scores
leaderboard.scores.add(1500, "player1")
leaderboard.scores.add(2300, "player2")
leaderboard.scores.add(1800, "player3")

# Get top 10 players (highest scores first)
top_players = leaderboard.scores.revrange(0, 9, withscores: true)
# => [["player2", 2300.0], ["player3", 1800.0], ["player1", 1500.0]]

# Get player rank (0-indexed, lower scores = lower rank)
rank = leaderboard.scores.rank("player1")  # => 0
rev_rank = leaderboard.scores.revrank("player1")  # => 2 (highest to lowest)

# Get score range
mid_tier = leaderboard.scores.rangebyscore(1000, 2000, withscores: true)

# Increment score atomically
leaderboard.scores.increment("player1", 100)  # Add 100 to existing score
```

### List-Based Queues and Feeds
Use Valkey/Redis lists for queues, feeds, and ordered data.

```ruby
class TaskQueue < Familia::Horreum
  identifier_field :queue_name
  field :queue_name
  list :tasks
end

class ActivityFeed < Familia::Horreum
  identifier_field :user_id
  field :user_id
  list :activities
end

# Task queue operations
queue = TaskQueue.new(queue_name: "email_processing")

# Add tasks to queue (right push)
queue.tasks.push({
  type: "send_email",
  recipient: "user@example.com",
  template: "welcome"
}.to_json)

# Process tasks (left pop - FIFO)
next_task = queue.tasks.pop  # Atomic pop from left
task_data = JSON.parse(next_task) if next_task

# Activity feed with size limit
feed = ActivityFeed.new(user_id: "user123")

# Add activity (keep last 100)
feed.activities.unshift("User logged in at #{Familia.now}")
feed.activities.trim(0, 99)  # Keep only last 100 items

# Get recent activities
recent = feed.activities.range(0, 9)  # Get 10 most recent
```

### Hash-Based Configuration Storage
Store structured configuration and key-value data.

```ruby
class UserPreferences < Familia::Horreum
  identifier_field :user_id
  field :user_id
  hash :settings
  hash :feature_flags
end

prefs = UserPreferences.new(user_id: "user123")

# UnsortedSet individual preferences
prefs.settings["theme"] = "dark"
prefs.settings["notifications"] = "true"
prefs.settings["timezone"] = "UTC-5"

# Batch set multiple values
prefs.feature_flags.update(
  "beta_ui" => "true",
  "new_dashboard" => "false",
  "advanced_features" => "true"
)

# Get preferences
theme = prefs.settings["theme"]     # => "dark"
all_settings = prefs.settings.to_h  # => Hash of all settings

# Check feature flags
beta_enabled = prefs.feature_flags["beta_ui"] == "true"
```

---

## Error Handling and Validation

### Connection Error Handling
Robust error handling for Valkey/Redis connection issues.

```ruby
class ResilientService < Familia::Horreum
  field :name, :data

  def self.with_fallback(&block)
    retries = 3
    begin
      yield
    rescue Redis::ConnectionError, Redis::TimeoutError => e
      retries -= 1
      if retries > 0
        sleep(0.1 * (4 - retries))  # Exponential backoff
        retry
      else
        Familia.warn "Database operation failed after retries: #{e.message}"
        nil  # Return nil or handle gracefully
      end
    end
  end

  def save_with_fallback
    self.class.with_fallback { save }
  end
end
```

### Data Validation Patterns
Implement validation in model classes.

```ruby
class User < Familia::Horreum
  field :email, :username, :age

  def valid?
    errors.clear
    validate_email
    validate_username
    validate_age
    errors.empty?
  end

  def errors
    @errors ||= []
  end

  private

  def validate_email
    unless email&.include?('@')
      errors << "Email must be valid"
    end
  end

  def validate_username
    if username.nil? || username.length < 3
      errors << "Username must be at least 3 characters"
    end
  end

  def validate_age
    unless age.is_a?(Integer) && age > 0
      errors << "Age must be a positive integer"
    end
  end
end

# Usage
user = User.new(email: "invalid", username: "ab", age: -5)
if user.valid?
  user.save
else
  puts "Validation errors: #{user.errors.join(', ')}"
end
```

---

## Performance Optimization

### Pipelined Bulk Loading

Load multiple objects efficiently with a single pipelined Redis batch.

```ruby
# Before: N×2 commands (EXISTS + HGETALL per object)
users = ids.map { |id| User.find_by_id(id) }
# For 14 objects: 28 Redis commands

# After: 1 pipelined batch
users = User.load_multi(ids)
# For 14 objects: 1 batch with 14 HGETALL commands (2× faster)

# Load by full dbkeys
users = User.load_multi_by_keys(['user:123:object', 'user:456:object'])

# Filter out nils for missing objects
existing_users = User.load_multi(ids).compact
```

### Optional EXISTS Check Optimization

Skip the EXISTS check for 50% reduction in Redis commands when keys are known to exist.

```ruby
# Default behavior (2 commands: EXISTS + HGETALL)
user = User.find_by_id(123)

# Optimized (1 command: HGETALL only)
user = User.find_by_id(123, check_exists: false)
```

**When to use `check_exists: false`:**
- Loading from sorted set results (keys guaranteed to exist)
- High-throughput API endpoints
- Bulk operations with known-existing keys

### Batch Operations
Minimize Valkey/Redis round trips with batch operations.

```ruby
# Instead of multiple individual operations
users = []
100.times do |i|
  user = User.new(name: "User #{i}", email: "user#{i}@example.com")
  users << user
end

# Use transactions for batch saves
User.pipelined do
  users.each do |user|
    # All operations batched in pipeline
    user.save
  end
end
```

### Index Rebuilding

Auto-generated rebuild methods for unique and multi indexes with zero downtime.

```ruby
class User < Familia::Horreum
  feature :relationships
  unique_index :email, :email_lookup
end

# Rebuild class-level unique index
User.rebuild_email_lookup

# With progress tracking
User.rebuild_email_lookup(batch_size: 100) do |progress|
  puts "#{progress[:completed]}/#{progress[:total]}"
end

# Instance-scoped index rebuild
company.rebuild_badge_index
```

**When to use:**
- After data migrations or bulk imports
- Recovering from index corruption
- Adding indexes to existing data

### Memory Optimization
Efficient memory usage patterns.

```ruby
class CacheEntry < Familia::Horreum
  feature :expiration

  field :key, :value, :created_at
  default_expiration 1.hour

  # Use shorter field names to reduce memory
  field :k, :v, :c  # Instead of key, value, created_at

  # Compress large values
  def value=(val)
    @value = val.length > 1000 ? Zlib.deflate(val) : val
  end

  def value
    val = @value || ""
    val.start_with?("\x78\x9c") ? Zlib.inflate(val) : val
  rescue Zlib::DataError
    @value  # Return original if decompression fails
  end
end
```

### Connection Pool Sizing
Configure connection pools based on application needs.

```ruby
# High-throughput application
Familia.connection_provider = lambda do |uri|
  ConnectionPool.new(size: 25, timeout: 5) do
    Redis.new(url: uri)
  end.with { |conn| conn }
end

# Memory-constrained environment
Familia.connection_provider = lambda do |uri|
  ConnectionPool.new(size: 5, timeout: 10) do
    Redis.new(url: uri)
  end.with { |conn| conn }
end
```

---

## Migration and Upgrading

### From v1.x to v2.0
Key changes and migration steps.

```ruby
# OLD v1.x syntax
class User < Familia
  identifier :email
  string :name
  list :sessions
end

# NEW v2.0 syntax
class User < Familia::Horreum
  identifier_field :email  # Updated method name
  field :name              # Generic field method
  list :sessions           # Data types unchanged
end

# Feature activation (NEW)
class User < Familia::Horreum
  feature :expiration      # Explicit feature activation
  feature :safe_dump

  identifier_field :email
  field :name
  list :sessions

  default_expiration 24.hours  # Feature-specific methods
  safe_dump_field :name       # Feature-specific methods
end
```

### Encryption Migration
Migrating existing fields to encrypted storage.

```ruby
# Step 1: Add feature without changing existing fields
class User < Familia::Horreum
  feature :encrypted_fields  # Add feature

  field :name, :email
  field :api_key    # Still plaintext during migration
end

# Step 2: Migrate data with dual read/write
class User < Familia::Horreum
  feature :encrypted_fields

  field :name, :email
  encrypted_field :api_key  # Now encrypted

  # Temporary migration method
  def migrate_api_key!
    if raw_api_key = dbclient.hget(dbkey, "api_key")  # Read old plaintext
      self.api_key = raw_api_key                       # Write as encrypted
      dbclient.hdel(dbkey, "api_key")                 # Remove plaintext
      save
    end
  end
end

# Step 3: Run migration for existing users
User.instances.each(&:migrate_api_key!)
```

---

## Testing Patterns

### Test Helpers and Utilities
Common patterns for testing Familia applications.

```ruby
# test_helper.rb
require 'familia'

# Use separate Valkey/Redis database for tests
Familia.configure do |config|
  config.uri = ENV.fetch('REDIS_TEST_URI', 'redis://localhost:2525/3')
end

module TestHelpers
  def setup_redis
    # Clear test database
    Familia.dbclient.flushdb
  end

  def teardown_redis
    Familia.dbclient.flushdb
  end

  def create_test_user(**attrs)
    User.new({
      email: "test@example.com",
      name: "Test User",
      created_at: Familia.now.to_i
    }.merge(attrs))
  end
end

# In test files
class UserTest < Minitest::Test
  include TestHelpers

  def setup
    setup_redis
  end

  def teardown
    teardown_redis
  end

  def test_user_creation_with_automatic_indexing
    user = create_test_user(name: "Alice")
    user.save  # Automatically adds to class-level indexes

    assert user.exists?
    assert_equal "Alice", user.name

    # Test automatic indexing (if using unique_index)
    if User.respond_to?(:find_by_email)
      found_user = User.find_by_email(user.email)
      assert_equal user.identifier, found_user.identifier
    end
  end

  def test_relationships_with_clean_syntax
    user = create_test_user
    user.save  # Automatic class-level tracking

    domain = Domain.new(domain_id: "test_domain", name: "test.com")
    domain.save  # Automatic class-level tracking

    # Test clean relationship syntax
    user.domains << domain  # Ruby-like collection syntax
    assert domain.in_user_domains?(user.identifier)
    assert user.domains.member?(domain.identifier)
  end

  def test_encrypted_fields_concealment
    setup_encryption_keys

    vault = SecureVault.new(
      name: "Test Vault",
      secret_key: "super-secret-123",
      api_token: "sk-1234567890"
    )
    vault.save

    # Test ConcealedString behavior
    assert_instance_of Familia::Features::EncryptedFields::ConcealedString, vault.secret_key
    assert_equal "[CONCEALED]", vault.secret_key.to_s
    assert_equal "super-secret-123", vault.secret_key.reveal

    # Test JSON safety
    json_data = vault.to_json
    refute_includes json_data, "super-secret-123"
    assert_includes json_data, "[CONCEALED]"
  end

  def test_transient_fields_non_persistence
    form = LoginForm.new(
      username: "testuser",
      password: "secret123",
      csrf_token: "abc123"
    )
    form.save

    # Reload and verify transient fields not persisted
    reloaded = LoginForm.load(form.identifier)
    assert_equal "testuser", reloaded.username
    assert_nil reloaded.password
    assert_nil reloaded.csrf_token
  end

  def test_object_identifier_generation
    # Test UUID generation
    doc = UuidDocument.create(title: "Test Doc")
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i, doc.objid)

    # Test hex generation
    session = HexSession.create(user_id: "123")
    assert_match(/\A[0-9a-f]+\z/i, session.objid)
    assert_equal 16, session.objid.length
  end

  def test_quantization_time_bucketing
    timestamp = Time.parse("2024-12-15 14:37:23")
    bucket = MetricsBucket.quantize_timestamp(timestamp)
    assert_equal "20241215_1430", bucket  # 10-minute bucket

    # Test multiple timestamps in same bucket
    timestamp2 = Time.parse("2024-12-15 14:39:45")
    bucket2 = MetricsBucket.quantize_timestamp(timestamp2)
    assert_equal bucket, bucket2
  end

  def test_external_identifier_mapping
    user = ExternalUser.new(name: "External User")
    user.save

    # Test external ID is derived from objid
    assert_not_nil user.objid
    assert_not_nil user.extid
    assert user.extid.start_with?("ext_")

    # Test deterministic generation
    user2 = ExternalUser.new(objid: user.objid, name: "External User")
    assert_equal user.extid, user2.extid
  end

  private

  def setup_encryption_keys
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
end
```

---

## Resources and References

### Key Configuration
Essential configuration options for Familia v2.0.0-pre.

```ruby
Familia.configure do |config|
  # Basic Valkey/Redis connection
  config.uri = ENV['REDIS_URL'] || 'redis://localhost:6379/0'

  # Connection provider for pooling (optional)
  config.connection_provider = MyConnectionProvider

  # Encryption configuration (for encrypted_fields feature)
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY_V1'],
    v2: ENV['FAMILIA_ENCRYPTION_KEY_V2']
  }
  config.current_key_version = :v2

  # Debugging and logging
  config.debug = ENV['FAMILIA_DEBUG'] == 'true'
  config.enable_database_logging = ENV['FAMILIA_LOG_REDIS'] == 'true'
end
```

### Documentation Links
- [Familia Repository](https://github.com/delano/familia)
- [Wiki Home](../guides/Home.md)
- [Feature System Guide](../guides/Feature-System-Guide.md)
- [Relationships Guide](../guides/Relationships-Guide.md)
- [Encrypted Fields Overview](../guides/Encrypted-Fields-Overview.md)
- [Connection Pooling Guide](../guides/Connection-Pooling-Guide.md)

### Version Information
- **Current Version**: v2.0.0
- **Ruby Compatibility**: 3.3+ (3.4+ recommended for optimal threading)
- **Redis Compatibility**: 6.0+ (Valkey compatible)

This technical reference covers the major components and usage patterns available in Familia v2.0. For complete API documentation, see the generated YARD docs and wiki guides.
