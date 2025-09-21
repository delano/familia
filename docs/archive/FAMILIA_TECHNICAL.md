# Familia v2.0.0-pre Series Technical Reference

**Familia** is a Ruby ORM for Redis/Valkey providing object mapping, relationships, and advanced features like encryption, connection pooling, and permission systems. This technical reference covers the major classes, methods, and usage patterns introduced in the v2.0.0-pre series.

---

## Core Architecture

### Base Classes

#### `Familia::Horreum` - Primary ORM Base Class
The main base class for Redis-backed objects, similar to ActiveRecord models.

```ruby
class User < Familia::Horreum
  # Basic field definitions
  field :name, :email, :created_at

  # Redis data types as instance variables
  list :sessions      # Redis list
  set :tags          # Redis set
  sorted_set :scores # Redis sorted set
  hash :settings     # Redis hash
end
```

**Key Methods:**
- `save` - Persist object to Redis
- `save_if_not_exists` - Conditional persistence (v2.0.0-pre6)
- `load` - Load object from Redis
- `exists?` - Check if object exists in Redis
- `destroy` - Remove object from Redis

#### `Familia::DataType` - Redis Data Type Wrapper
Base class for Redis data type implementations.

**Registered Types:**
- `String` - Redis strings
- `List` - Redis lists
- `UnsortedSet` - Redis sets
- `SortedSet` - Redis sorted sets
- `HashKey` - Redis hashes
- `Counter` - Atomic counters
- `Lock` - Distributed locks

---

## Feature System (v2.0.0-pre5+)

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
  safe_dump_fields :name, :email  # Only these fields in safe_dump
end

user = User.new(name: "Alice", email: "alice@example.com", password_hash: "secret")
user.safe_dump  # => {"name" => "Alice", "email" => "alice@example.com"}
```

#### 3. Encrypted Fields Feature (v2.0.0-pre5)
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

**Security Features:**
- Field-specific key derivation for domain separation
- Key versioning and rotation support
- Memory-safe key handling
- Configurable encryption algorithms

#### 4. Transient Fields Feature (v2.0.0-pre5)
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

#### 5. Relationships Feature (v2.0.0-pre7)
Comprehensive object relationship system with three relationship types.

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email

  # Collections for storing related object IDs
  set :domains           # Simple set
  sorted_set :activity   # Scored/sorted collection

  # Indexed lookups (O(1) hash-based)
  indexed_by :email_lookup, field: :email

  # Global tracking with scoring
  tracked_in :all_customers, type: :sorted_set, score: :created_at
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name, :status

  # Bidirectional membership
  member_of Customer, :domains, type: :set

  # Conditional tracking with lambda scoring
  tracked_in :active_domains, type: :sorted_set,
    score: ->(domain) { domain.status == 'active' ? Familia.now.to_i : 0 }
end
```

**Relationship Operations:**

```ruby
# Create objects
customer = Customer.new(custid: "cust123", name: "Acme Corp")
domain = Domain.new(domain_id: "dom456", name: "acme.com", status: "active")

# Establish bidirectional relationship
domain.add_to_customer_domains(customer.custid)
customer.domains.add(domain.identifier)

# Query relationships
domain.in_customer_domains?(customer.custid)  # => true
customer.domains.member?(domain.identifier)   # => true

# Indexed lookups
Customer.add_to_email_lookup(customer)
found_id = Customer.email_lookup.get(customer.email)  # O(1) lookup

# Global tracking
Customer.add_to_all_customers(customer)
recent = Customer.all_customers.range_by_score(
  (Familia.now - 24.hours).to_i, '+inf'
)
```

---

## Connection Management (v2.0.0-pre+)

### Connection Provider Pattern
Flexible connection pooling with provider-based architecture.

```ruby
# Basic Redis connection
Familia.configure do |config|
  config.redis_uri = "redis://localhost:6379/0"
end

# Connection pooling with ConnectionPool gem
require 'connection_pool'

Familia.connection_provider = lambda do |uri|
  parsed = URI.parse(uri)
  pool_key = "#{parsed.host}:#{parsed.port}/#{parsed.db || 0}"

  @pools ||= {}
  @pools[pool_key] ||= ConnectionPool.new(size: 10, timeout: 5) do
    Redis.new(
      host: parsed.host,
      port: parsed.port,
      db: parsed.db || 0,
      connect_timeout: 1,
      read_timeout: 1,
      write_timeout: 1
    )
  end

  @pools[pool_key].with { |conn| yield conn if block_given?; conn }
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

## Advanced Relationship Patterns

### Permission-Encoded Relationships (v2.0.0-pre7)
Combine timestamps with permission bits for access control.

```ruby
class Document < Familia::Horreum
  feature :relationships

  identifier_field :doc_id
  field :doc_id, :title, :content

  # Permission constants (bit flags)
  READ    = 1   # 001
  WRITE   = 2   # 010
  DELETE  = 4   # 100
  ADMIN   = 8   # 1000
end

class UserDocumentAccess
  # Encode timestamp + permissions into sorted set score
  def self.encode_score(timestamp, permissions)
    "#{timestamp}.#{permissions}".to_f
  end

  def self.decode_score(score)
    parts = score.to_s.split('.')
    timestamp = parts[0].to_i
    permissions = parts[1] ? parts[1].to_i : 0
    [timestamp, permissions]
  end

  # Check if user has specific permission
  def self.has_permission?(permissions, required)
    (permissions & required) != 0
  end
end

# Usage example
user_id = "user123"
doc_id = "doc456"
timestamp = Familia.now.to_i

# Grant read + write permissions
permissions = Document::READ | Document::WRITE  # 3
score = UserDocumentAccess.encode_score(timestamp, permissions)

# Store in sorted set (user_id -> score with permissions)
user_documents = Familia::DataType::SortedSet.new("user:#{user_id}:documents")
user_documents.add(doc_id, score)

# Query with permission filtering
docs_with_write = user_documents.select do |doc_id, score|
  _, permissions = UserDocumentAccess.decode_score(score)
  UserDocumentAccess.has_permission?(permissions, Document::WRITE)
end
```

### Time-Series Relationships
Track relationships over time with timestamp-based scoring.

```ruby
class ActivityTracker < Familia::Horreum
  feature :relationships

  # Track user activities with timestamps
  tracked_in :user_activities, type: :sorted_set,
    score: ->(activity) { activity.created_at }

  # Track by activity type
  tracked_in :activity_by_type, type: :sorted_set,
    score: ->(activity) { "#{activity.activity_type}:#{activity.created_at}".hash }

  field :user_id, :activity_type, :data, :created_at
end

# Query recent activities (last hour)
hour_ago = (Familia.now - 1.hour).to_i
recent_activities = ActivityTracker.user_activities.range_by_score(
  hour_ago, '+inf', limit: [0, 50]
)

# Get activities by type in time range
login_activities = ActivityTracker.activity_by_type.range_by_score(
  "login:#{hour_ago}".hash, "login:#{Familia.now.to_i}".hash
)
```

---

## Data Type Usage Patterns

### Advanced Sorted UnsortedSet Operations
Leverage Redis sorted sets for rankings, time series, and scored data.

```ruby
class Leaderboard < Familia::Horreum
  identifier_field :game_id
  field :game_id, :name
  sorted_set :scores
end

leaderboard = Leaderboard.new(game_id: "game1", name: "Daily Challenge")

# Add player scores
leaderboard.scores.add("player1", 1500)
leaderboard.scores.add("player2", 2300)
leaderboard.scores.add("player3", 1800)

# Get top 10 players
top_players = leaderboard.scores.range(0, 9, with_scores: true, order: 'DESC')
# => [["player2", 2300.0], ["player3", 1800.0], ["player1", 1500.0]]

# Get player rank
rank = leaderboard.scores.rank("player1", order: 'DESC')  # => 2 (0-indexed)

# Get score range
mid_tier = leaderboard.scores.range_by_score(1000, 2000, with_scores: true)

# Increment score atomically
leaderboard.scores.increment("player1", 100)  # Add 100 to existing score
```

### List-Based Queues and Feeds
Use Redis lists for queues, feeds, and ordered data.

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

# Set individual preferences
prefs.settings.set("theme", "dark")
prefs.settings.set("notifications", "true")
prefs.settings.set("timezone", "UTC-5")

# Batch set multiple values
prefs.feature_flags.update({
  "beta_ui" => "true",
  "new_dashboard" => "false",
  "advanced_features" => "true"
})

# Get preferences
theme = prefs.settings.get("theme")  # => "dark"
all_settings = prefs.settings.all    # => Hash of all settings

# Check feature flags
beta_enabled = prefs.feature_flags.get("beta_ui") == "true"
```

---

## Error Handling and Validation

### Connection Error Handling
Robust error handling for Redis connection issues.

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
        Familia.warn "Redis operation failed after retries: #{e.message}"
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

### Batch Operations
Minimize Redis round trips with batch operations.

```ruby
# Instead of multiple individual operations
users = []
100.times do |i|
  user = User.new(name: "User #{i}", email: "user#{i}@example.com")
  users << user
end

# Use Redis pipelining for batch saves
User.transaction do |redis|
  users.each do |user|
    # All operations batched in transaction
    user.object.set_all(user.to_hash)
    User.email_index.set(user.email, user.identifier)
  end
end
```

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
    Redis.new(uri, connect_timeout: 0.1, read_timeout: 1, write_timeout: 1)
  end.with { |conn| yield conn if block_given?; conn }
end

# Memory-constrained environment
Familia.connection_provider = lambda do |uri|
  ConnectionPool.new(size: 5, timeout: 10) do
    Redis.new(uri, connect_timeout: 2, read_timeout: 5, write_timeout: 5)
  end.with { |conn| yield conn if block_given?; conn }
end
```

---

## Migration and Upgrading

### From v1.x to v2.0.0-pre
Key changes and migration steps.

```ruby
# OLD v1.x syntax
class User < Familia
  identifier :email
  string :name
  list :sessions
end

# NEW v2.0.0-pre syntax
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
  safe_dump_fields :name       # Feature-specific methods
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
    if raw_api_key = object.get("api_key")  # Read old plaintext
      self.api_key = raw_api_key             # Write as encrypted
      object.delete("api_key")               # Remove plaintext
      save
    end
  end
end

# Step 3: Run migration for all users
User.all.each(&:migrate_api_key!)
```

---

## Testing Patterns

### Test Helpers and Utilities
Common patterns for testing Familia applications.

```ruby
# test_helper.rb
require 'familia'

# Use separate Redis database for tests
Familia.configure do |config|
  config.redis_uri = ENV.fetch('REDIS_TEST_URI', 'redis://localhost:6379/15')
end

module TestHelpers
  def setup_redis
    # Clear test database
    Familia.connection.flushdb
  end

  def teardown_redis
    Familia.connection.flushdb
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

  def test_user_creation
    user = create_test_user(name: "Alice")
    user.save

    assert user.exists?
    assert_equal "Alice", user.name
  end

  def test_relationships
    user = create_test_user
    user.save

    domain = Domain.new(domain_id: "test_domain", name: "test.com")
    domain.save

    # Test relationship
    domain.add_to_user_domains(user.identifier)
    assert domain.in_user_domains?(user.identifier)
  end
end
```

---

## Resources and References

### Key Configuration
Essential configuration options for Familia v2.0.0-pre.

```ruby
Familia.configure do |config|
  # Basic Redis connection
  config.redis_uri = ENV['REDIS_URL'] || 'redis://localhost:6379/0'

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
- [Wiki Home](docs/wiki/Home.md)
- [Feature System Guide](docs/wiki/Feature-System-Guide.md)
- [Relationships Guide](docs/wiki/Relationships-Guide.md)
- [Encrypted Fields Overview](docs/wiki/Encrypted-Fields-Overview.md)
- [Connection Pooling Guide](docs/wiki/Connection-Pooling-Guide.md)

### Version Information
- **Current Version**: v2.0.0.pre6 (as of version.rb)
- **Target Version**: v2.0.0.pre7 (relationships release)
- **Ruby Compatibility**: 3.0+ (3.4+ recommended for optimal threading)
- **Redis Compatibility**: 6.0+ (Valkey compatible)

This technical reference covers the major components and usage patterns available in Familia v2.0.0-pre series. For complete API documentation, see the generated YARD docs and wiki guides.
