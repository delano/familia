# Familia v2.0.0-pre Series Technical Reference

**Familia** is a Ruby ORM for Redis/Valkey providing object mapping, relationships, and advanced features like encryption, connection pooling, and permission systems. This technical reference covers the major classes, methods, and usage patterns introduced in the v2.0.0-pre series.

> For conceptual understanding and getting started with Familia, see the [Overview Guide](../overview.md). This document provides detailed implementation patterns and advanced configuration options.

---

## Core Architecture

### Base Classes

#### `Familia::Horreum` - Primary ORM Base Class
The main base class for Redis-backed objects, similar to ActiveRecord models.

```ruby
class User < Familia::Horreum
  # Basic field definitions
  field :name, :email, :created_at

  # Valkey/Redis data types as instance variables
  list :sessions      # Valkey/Redis list
  set :tags          # Valkey/Redis set
  sorted_set :scores # Valkey/Redis sorted set
  hash :settings     # Valkey/Redis hash
end
```

**Key Methods:**
- `save` - Persist object to Redis
- `save_if_not_exists` - Conditional persistence (v2.0.0-pre6)
- `load` - Load object from Redis
- `exists?` - Check if object exists in Redis
- `destroy` - Remove object from Redis

#### `Familia::DataType` - Valkey/Redis Data Type Wrapper
Base class for Valkey/Redis data type implementations.

**Registered Types:**
- `String` - Valkey/Redis strings
- `List` - Valkey/Redis lists
- `UnsortedSet` - Valkey/Redis sets
- `SortedSet` - Valkey/Redis sorted sets
- `HashKey` - Valkey/Redis hashes
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
  safe_dump_field :name, :email  # Only these fields in safe_dump
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

**Advanced Security Implementation:**
```ruby
# Multiple encryption providers with fallback
class CriticalData < Familia::Horreum
  feature :encrypted_fields

  # Configure encryption provider preference
  set_encryption_provider :xchacha20_poly1305  # Preferred
  set_fallback_provider :aes_gcm               # Fallback

  encrypted_field :credit_card, aad_fields: [:user_id, :created_at]
  encrypted_field :ssn, provider: :xchacha20_poly1305  # Force specific provider
  encrypted_field :notes  # Uses default provider
end

# Key versioning and rotation
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['OLD_KEY'],      # Legacy key
    v2: ENV['CURRENT_KEY'],  # Current key
    v3: ENV['NEW_KEY']       # New key for rotation
  }
  config.current_key_version = :v2

  # Provider configuration
  config.encryption_providers = {
    xchacha20_poly1305: {
      key_size: 32,
      nonce_size: 24,
      require_gem: 'rbnacl'
    },
    aes_gcm: {
      key_size: 32,
      iv_size: 12,
      tag_size: 16
    }
  }
end

# Request-level key caching for performance
Familia::Encryption.with_request_cache do
  1000.times do |i|
    record = CriticalData.new(
      credit_card: "4111-1111-1111-#{i.to_s.rjust(4, '0')}",
      ssn: "123-45-#{i.to_s.rjust(4, '0')}",
      notes: "Customer record #{i}"
    )
    record.save  # Reuses derived keys for performance
  end
end

# Key rotation procedures
CriticalData.all.each do |record|
  # Re-encrypt with current key version
  record.re_encrypt_fields!

  # Verify encryption status
  status = record.encrypted_fields_status
  puts "Record #{record.identifier}: #{status}"
  # => {credit_card: {encrypted: true, key_version: :v2, provider: :xchacha20_poly1305}}
end
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
Comprehensive object relationship system with automatic management, clean Ruby-idiomatic syntax, and simplified method generation.

```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email

  # Collections for storing related object IDs
  set :domains           # Simple set
  sorted_set :activity   # Scored/sorted collection

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
  indexed_by :name, :domain_index, parent: Customer

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

#### 6. Object Identifier Feature (v2.0.0-pre7)
Automatic generation of unique object identifiers with configurable strategies.

```ruby
class Document < Familia::Horreum
  feature :object_identifier, generator: :uuid_v4

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
- `:uuid_v4` - Standard UUID v4 format (36 characters)
- `:hex` - Hexadecimal strings (configurable length, default 12)
- `:custom` - User-defined generator method

**Technical Implementation:**
```ruby
# Auto-generated on object creation
doc = Document.create(title: "My Document")
doc.objid  # => "f47ac10b-58cc-4372-a567-0e02b2c3d479"

session = Session.create(user_id: "123")
session.objid  # => "a1b2c3d4e5f67890"

# Custom identifier validation
api_key = ApiKey.create(name: "Production API")
api_key.objid  # => "ak_Xy9ZaBcD3fG8HjKlMnOpQrStUvWxYz12"

# Collision detection and retry logic
Document.feature_options(:object_identifier)
#=> {generator: :uuid_v4, max_retries: 3, collision_check: true}
```

#### 7. External Identifier Feature (v2.0.0-pre7)
Integration patterns for external system identifiers with validation and mapping.

```ruby
class ExternalUser < Familia::Horreum
  feature :external_identifier

  identifier_field :internal_id
  field :internal_id, :external_id, :name, :sync_status, :last_sync_at

  # External system validation
  validates_external_id_format /^ext_\d{6,}$/
  external_id_source "CustomerAPI"
end

class LegacyAccount < Familia::Horreum
  feature :external_identifier, prefix: "legacy"

  field :legacy_account_id, :migrated_at, :migration_status

  # Custom validation logic
  def valid_external_id?
    legacy_account_id.present? &&
    legacy_account_id.match?(/^LAC[A-Z]{2}\d{8}$/)
  end

  # Bidirectional mapping
  def self.find_by_legacy_id(legacy_id)
    mapping = external_id_mapping.get(legacy_id)
    mapping ? load(mapping) : nil
  end
end
```

**External ID Management:**
```ruby
# Create with external mapping
user = ExternalUser.new(
  internal_id: SecureRandom.uuid,
  external_id: "ext_123456",
  name: "John Doe"
)
user.save  # Automatically creates bidirectional mapping

# Lookup by external ID
found_user = ExternalUser.find_by_external_id("ext_123456")
external_id = found_user.external_id_mapping.get(found_user.internal_id)

# Batch external ID operations
external_ids = ["ext_123456", "ext_789012", "ext_345678"]
users = ExternalUser.multiget_by_external_ids(external_ids)

# Sync status tracking
user.mark_sync_pending
user.mark_sync_completed
user.mark_sync_failed(error_message)
user.sync_status  # => "completed", "pending", "failed"
```

#### 8. Quantization Feature (v2.0.0-pre7)
Advanced time-based data bucketing with configurable strategies and analytics integration.

```ruby
class MetricsBucket < Familia::Horreum
  feature :quantization

  identifier_field :metric_key
  field :metric_key, :bucket_timestamp, :value_count, :sum_value

  # Time-based quantization with 10-minute buckets
  quantize_time :bucket_timestamp, interval: 10.minutes, format: '%Y%m%d_%H%M'

  # Custom quantization strategy
  quantize_value :user_score, buckets: [0, 100, 500, 1000, 5000], labels: %w[bronze silver gold platinum diamond]
end

class AnalyticsBucket < Familia::Horreum
  feature :quantization

  field :event_type, :quantized_timestamp, :aggregated_count

  # Multiple quantization strategies
  quantize_time :hourly_bucket, interval: 1.hour, format: '%Y%m%d_%H'
  quantize_time :daily_bucket, interval: 1.day, format: '%Y%m%d'
  quantize_time :weekly_bucket, interval: 1.week, format: '%YW%U'

  # Geographic quantization
  quantize_geo :location_bucket, precision: :city  # :country, :state, :city, :zipcode
end
```

**Quantization Operations:**
```ruby
# Automatic time bucketing
timestamp = Time.now
bucket = MetricsBucket.quantize_timestamp(timestamp)
# => "20241215_1430" (for 2:37 PM becomes 2:30 PM bucket)

# Value bucketing with labels
score = 750
bucket_label = MetricsBucket.quantize_user_score(score)
# => "gold" (750 falls in 500-1000 range)

# Analytics aggregation
events = [
  {timestamp: Time.now - 5.minutes, count: 10},
  {timestamp: Time.now - 3.minutes, count: 15},
  {timestamp: Time.now + 2.minutes, count: 8}
]

# All events quantized to same 10-minute bucket
bucketed = events.map { |e| AnalyticsBucket.quantize_timestamp(e[:timestamp]) }
# => ["20241215_1430", "20241215_1430", "20241215_1430"]

# Geographic bucketing
coordinates = {lat: 40.7128, lng: -74.0060}  # NYC
geo_bucket = AnalyticsBucket.quantize_location(coordinates)
# => "US_NY_NYC" (country_state_city)

# Range queries with quantized data
start_bucket = AnalyticsBucket.quantize_timestamp(Time.now - 1.hour)
end_bucket = AnalyticsBucket.quantize_timestamp(Time.now)
hourly_data = AnalyticsBucket.range_by_quantized_time(start_bucket, end_bucket)
```

**Performance Optimization Patterns:**
```ruby
class HighVolumeMetrics < Familia::Horreum
  feature :quantization

  # Pre-aggregated counters for efficiency
  counter :event_count, quantize: [5.minutes, '%H%M']
  sorted_set :top_events, quantize: [1.hour, '%Y%m%d_%H']

  # Efficient increment operations
  def self.record_event(event_type, score = nil)
    current_bucket = quantize_timestamp(Familia.now)

    # Atomic increment
    quantized_counter = counter("#{event_type}:#{current_bucket}")
    quantized_counter.increment

    # Optional scoring
    if score
      quantized_scores = sorted_set("scores:#{current_bucket}")
      quantized_scores.add(event_type, score)
    end
  end
end
```

---

## Advanced Feature System Architecture (v2.0.0-pre7)

### Feature Autoloader for Complex Projects
Organize features into modular files for large applications.

```ruby
# app/models/customer.rb - Main model file
class Customer < Familia::Horreum
  module Features
    include Familia::Features::Autoloader
    # Automatically loads all .rb files from app/models/customer/features/
  end

  # Core model definition
  identifier_field :custid
  field :custid, :name, :email, :created_at
end

# app/models/customer/features/notifications.rb
module Customer::Features::Notifications
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

# app/models/customer/features/analytics.rb
module Customer::Features::Analytics
  extend ActiveSupport::Concern

  included do
    # Add analytics tracking to core model
    feature :relationships
    class_participates_in :customer_analytics, score: :created_at
  end

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

### Feature Dependencies and Loading Order
Control feature loading sequence with dependency declarations.

```ruby
# lib/features/advanced_encryption.rb
module AdvancedEncryption
  extend Familia::Features::Autoloadable

  def self.depends_on
    [:encrypted_fields, :safe_dump]  # Required features
  end

  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    def encrypt_all_fields!
      # Batch encrypt all existing records
      all_records.each(&:re_encrypt_fields!)
    end

    def encryption_health_check
      # Validate encryption across all records
      failed_records = []
      all_records.each do |record|
        unless record.encrypted_fields_status.all? { |_, status| status[:encrypted] }
          failed_records << record.identifier
        end
      end
      failed_records
    end
  end

  def secure_export
    # Combine safe_dump with additional security
    exported = safe_dump
    exported[:export_timestamp] = Familia.now.to_i
    exported[:checksum] = Digest::SHA256.hexdigest(exported.to_json)
    exported
  end
end

# Usage with automatic dependency resolution
class SecureCustomer < Familia::Horreum
  feature :advanced_encryption  # Automatically includes dependencies

  field :name, :email
  encrypted_field :api_key, :private_notes
  safe_dump_field :name, :email
end
```

### Per-Class Feature Configuration Isolation
Each class maintains independent feature options.

```ruby
class PrimaryCache < Familia::Horreum
  feature :expiration, cascade_to: [:secondary_cache]
  feature :quantization, time_buckets: [1.hour, 6.hours, 1.day]

  field :cache_key, :value, :hit_count
  default_expiration 24.hours
end

class SecondaryCache < Familia::Horreum
  feature :expiration, cascade_to: []  # No further cascading
  feature :quantization, time_buckets: [1.day, 1.week]  # Different buckets

  field :cache_key, :backup_value, :backup_timestamp
  default_expiration 7.days
end

# Feature options are completely isolated
PrimaryCache.feature_options(:expiration)
#=> {cascade_to: [:secondary_cache]}

SecondaryCache.feature_options(:expiration)
#=> {cascade_to: []}

PrimaryCache.feature_options(:quantization)
#=> {time_buckets: [3600, 21600, 86400]}

SecondaryCache.feature_options(:quantization)
#=> {time_buckets: [86400, 604800]}
```

### Runtime Feature Management
Add, remove, and configure features dynamically.

```ruby
class DynamicModel < Familia::Horreum
  field :name, :status

  def self.enable_feature_set(feature_set)
    case feature_set
    when :basic
      feature :expiration
      feature :safe_dump
    when :secure
      feature :expiration
      feature :encrypted_fields
      feature :safe_dump
    when :analytics
      feature :expiration
      feature :relationships
      feature :quantization
    end
  end

  def self.feature_enabled?(feature_name)
    features_enabled.include?(feature_name.to_sym)
  end

  def self.disable_feature(feature_name)
    # Remove feature from enabled list (affects new instances)
    features_enabled.delete(feature_name.to_sym)
    remove_feature_options(feature_name)
  end
end

# Runtime configuration
DynamicModel.enable_feature_set(:analytics)
DynamicModel.feature_enabled?(:relationships)  # => true

# Conditional feature usage
if DynamicModel.feature_enabled?(:encrypted_fields)
  DynamicModel.encrypted_field :sensitive_data
end
```

---

## Connection Management (v2.0.0-pre+)

### Connection Provider Pattern
Flexible connection pooling with provider-based architecture.

```ruby
# Basic Valkey/Redis connection
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

### Time-Series Relationships with Automatic Management
Track relationships over time with timestamp-based scoring and automatic updates.

```ruby
class ActivityTracker < Familia::Horreum
  feature :relationships

  identifier_field :activity_id
  field :activity_id, :user_id, :activity_type, :data, :created_at

  # Class-level tracking with automatic management
  class_participates_in :user_activities, score: :created_at
  class_participates_in :activity_by_type,
                   score: ->(activity) { "#{activity.activity_type}:#{activity.created_at}".hash }
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
Leverage Valkey/Redis sorted sets for rankings, time series, and scored data.

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
Minimize Valkey/Redis round trips with batch operations.

```ruby
# Instead of multiple individual operations
users = []
100.times do |i|
  user = User.new(name: "User #{i}", email: "user#{i}@example.com")
  users << user
end

# Use Valkey/Redis pipelining for batch saves
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

# Use separate Valkey/Redis database for tests
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

  def test_user_creation_with_automatic_indexing
    user = create_test_user(name: "Alice")
    user.save  # Automatically adds to class-level indexes

    assert user.exists?
    assert_equal "Alice", user.name

    # Test automatic indexing
    found_id = User.email_lookup.get(user.email)
    assert_equal user.identifier, found_id
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
    user = ExternalUser.new(
      internal_id: SecureRandom.uuid,
      external_id: "ext_123456",
      name: "External User"
    )
    user.save

    # Test bidirectional mapping
    found_by_external = ExternalUser.find_by_external_id("ext_123456")
    assert_equal user.internal_id, found_by_external.internal_id

    # Test sync status tracking
    user.mark_sync_pending
    assert_equal "pending", user.sync_status

    user.mark_sync_completed
    assert_equal "completed", user.sync_status
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
- [Wiki Home](../guides/Home.md)
- [Feature System Guide](../guides/Feature-System-Guide.md)
- [Relationships Guide](../guides/Relationships-Guide.md)
- [Encrypted Fields Overview](../guides/Encrypted-Fields-Overview.md)
- [Connection Pooling Guide](../guides/Connection-Pooling-Guide.md)

### Version Information
- **Current Version**: v2.0.0.pre6 (as of version.rb)
- **Target Version**: v2.0.0.pre7 (relationships release)
- **Ruby Compatibility**: 3.0+ (3.4+ recommended for optimal threading)
- **Redis Compatibility**: 6.0+ (Valkey compatible)

This technical reference covers the major components and usage patterns available in Familia v2.0.0-pre series. For complete API documentation, see the generated YARD docs and wiki guides.
