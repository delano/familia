# Expiration Feature Guide

## Overview

The Expiration feature provides automatic Time-To-Live (TTL) management for Familia objects with support for class-level defaults, instance-level overrides, and cascading expiration to related fields. This feature ensures data retention policies are consistently enforced across your application.

## Core Concepts

### TTL Hierarchy

Familia uses a three-tier expiration system:

1. **Instance-level expiration** - Set on individual objects
2. **Class-level default expiration** - Inherited by all instances of the class
3. **Global default expiration** - Familia-wide fallback (`Familia.default_expiration`)

### Cascading Expiration

When a Horreum object has related fields (DataTypes), the expiration feature automatically cascades TTL updates to related objects that have their own `default_expiration` settings defined. This ensures consistent data lifecycle management while respecting per-field expiration policies.

## Basic Usage

### Enabling Expiration

```ruby
class Session < Familia::Horreum
  feature :expiration
  default_expiration 1.hour  # Class-level default

  identifier_field :session_id
  field :session_id, :user_id, :data
  list :activity_log
end
```

### Setting Class Defaults

```ruby
class UserSession < Familia::Horreum
  feature :expiration

  # Set default expiration for all instances
  default_expiration 30.minutes

  field :user_id, :ip_address, :csrf_token
end

# Can also set or update programmatically
UserSession.default_expiration(1.hour)
UserSession.default_expiration  # => 3600.0
```

### Instance-Level TTL Management

```ruby
session = UserSession.new(user_id: 123)

# Uses class default (1 hour)
session.default_expiration  # => 3600.0

# Set custom expiration for this instance
session.default_expiration = 15.minutes
session.default_expiration  # => 900.0

# Apply expiration to database
session.update_expiration  # Uses instance expiration (15 minutes)

# Or specify expiration inline
session.update_expiration(expiration: 5.minutes)
```

## Advanced Usage

### Inheritance and Parent Defaults

```ruby
class BaseSession < Familia::Horreum
  feature :expiration
  default_expiration 2.hours  # Parent default
end

class GuestSession < BaseSession
  # Inherits parent's 2-hour default
  field :temporary_data
end

class AdminSession < BaseSession
  # Override parent default
  default_expiration 8.hours
  field :admin_permissions
end

GuestSession.default_expiration  # => 7200.0 (2 hours from parent)
AdminSession.default_expiration  # => 28800.0 (8 hours, overridden)
```

### Cascading to Related Fields

```ruby
class Customer < Familia::Horreum
  feature :expiration
  default_expiration 24.hours

  identifier_field :customer_id
  field :customer_id, :name, :email
  list :recent_orders, default_expiration: 12.hours        # Will cascade
  set :favorite_categories   # Will NOT cascade (no default_expiration)
  hashkey :preferences, default_expiration: 6.hours       # Will cascade
end

customer = Customer.new(customer_id: 'cust_123')
customer.save

# This will set TTL on the main object AND related fields with default_expiration
customer.update_expiration(expiration: 12.hours)
# Sets expiration on:
# - customer:cust_123 (main hash) - 12 hours
# - customer:cust_123:recent_orders (list) - 12 hours
# - customer:cust_123:preferences (hashkey) - 12 hours
# - customer:cust_123:favorite_categories (set) - NO expiration (no default_expiration)
```

### TTL Status Checking

```ruby
session = UserSession.find('session_123')

# Check remaining TTL (returns seconds or special values)
ttl_seconds = session.ttl
case ttl_seconds
when -1
  puts "Session never expires (no TTL set)"
when -2
  puts "Session key doesn't exist"
when 0
  puts "Session has expired"
else
  puts "Session expires in #{ttl_seconds} seconds"
end

# Convenience methods for TTL status
session.expires?           # => true if TTL is set
session.expired?           # => true if TTL <= 0
session.expired?(5.minutes) # => true if TTL <= 300 seconds
```

### Expiration Extension and Removal

```ruby
session = UserSession.find('active_session')

# Extend current expiration by additional time
session.extend_expiration(15.minutes)  # Adds 15 minutes to current TTL

# Remove expiration entirely (persist indefinitely)
session.persist!  # Removes TTL, data won't expire

# Zero expiration also persists data (equivalent to persist!)
session.update_expiration(expiration: 0)  # No expiration set
```

### Conditional Expiration

```ruby
class AnalyticsEvent < Familia::Horreum
  feature :expiration

  identifier_field :event_id
  field :event_id, :event_type, :user_id, :timestamp, :data

  def should_expire?
    event_type == 'temporary' || timestamp < 1.day.ago
  end

  def save_with_conditional_expiration
    save

    if should_expire?
      update_expiration(expiration: 1.hour)
    else
      update_expiration(expiration: 30.days)
    end
  end
end
```

## Integration Patterns

### Rails Integration

```ruby
# app/models/user_session.rb
class UserSession < Familia::Horreum
  feature :expiration

  # Different TTLs based on Rails environment
  default_expiration case Rails.env
                     when 'development' then 8.hours   # Long for debugging
                     when 'test' then 1.minute         # Quick cleanup
                     when 'production' then 30.minutes # Security-focused
                     end

  identifier_field :session_token
  field :session_token, :user_id, :ip_address, :user_agent
  hashkey :flash_messages

  after_save :apply_expiration

  private

  def apply_expiration
    update_expiration
  end
end
```

### Background Job Integration

```ruby
class SessionCleanupJob
  include Sidekiq::Worker

  def perform
    # Extend expiration for active sessions
    UserSession.all.each do |session|
      if session.recently_active?
        session.update_expiration(expiration: 30.minutes)
      end
    end
  end
end

# Schedule cleanup
SessionCleanupJob.perform_in(5.minutes)
```

### Middleware Integration

```ruby
class SessionExpirationMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    session_token = extract_session_token(env)

    if session_token
      session = UserSession.find(session_token)

      # Extend session TTL on each request
      session&.update_expiration(expiration: 30.minutes)
    end

    @app.call(env)
  end

  private

  def extract_session_token(env)
    # Extract from cookies, headers, etc.
  end
end
```

## TTL Monitoring and Management

### Checking Current TTL

```ruby
session = UserSession.find('session_123')

# Check TTL using Valkey/Redis TTL command (returns seconds remaining)
ttl_seconds = session.ttl  # e.g., 1800 (30 minutes left)

# Convert to more readable format
case ttl_seconds
when -1
  puts "Session never expires"
when -2
  puts "Session key doesn't exist"
when 0
  puts "Session has expired"
when 0..3600
  puts "Session expires in #{ttl_seconds / 60} minutes"
else
  puts "Session expires in #{ttl_seconds / 3600} hours"
end
```

### Batch TTL Updates

```ruby
class SessionManager
  def self.extend_all_sessions(new_ttl)
    UserSession.all.each do |session|
      session.update_expiration(expiration: new_ttl)
    end
  end

  def self.expire_inactive_sessions
    UserSession.all.select(&:inactive?).each do |session|
      # Set very short TTL for inactive sessions
      session.update_expiration(expiration: 5.minutes)
    end
  end

  def self.make_sessions_permanent
    # Remove expiration from all sessions
    UserSession.all.each do |session|
      session.persist!  # Remove TTL entirely
    end
  end
end
```

### TTL-Based Data Lifecycle

```ruby
class DataRetentionService
  TTL_POLICIES = {
    guest_session: 30.minutes,
    user_session: 2.hours,
    admin_session: 8.hours,
    analytics_event: 30.days,
    audit_log: 1.year,
    temporary_upload: 1.hour
  }.freeze

  def self.apply_retention_policies
    TTL_POLICIES.each do |data_type, ttl|
      model_class = data_type.to_s.pascalize.constantize

      model_class.all.each do |record|
        record.update_expiration(expiration: ttl)
      end
    end
  end
end

# Run as scheduled job
DataRetentionService.apply_retention_policies
```

## Performance Considerations

### Efficient TTL Updates

```ruby
# ❌ Inefficient: Multiple round trips
sessions.each do |session|
  session.update_expiration(expiration: 1.hour)
end

# ✅ Efficient: Batch operations
redis = Familia.dbclient
pipeline = redis.pipelined do |pipe|
  sessions.each do |session|
    pipe.expire(session.dbkey, 3600)

    # Also expire related fields if needed
    session.class.related_fields.each do |name, definition|
      next if definition.opts[:default_expiration].nil?

      related_key = "#{session.dbkey}:#{name}"
      pipe.expire(related_key, 3600)
    end
  end
end
```

### Avoiding Expiration Conflicts

```ruby
class ResilientSession < Familia::Horreum
  feature :expiration
  default_expiration 30.minutes

  field :user_id, :data

  def safe_update_expiration(new_ttl = nil)
    new_ttl ||= default_expiration

    # Only update if key exists
    return unless exists?

    begin
      update_expiration(expiration: new_ttl)
    rescue => e
      # Log error but don't crash the application
      Familia.logger.warn "Failed to update expiration for #{dbkey}: #{e.message}"
      false
    end
  end
end
```

## Error Handling and Validation

### Expiration Value Validation

```ruby
session = UserSession.new(session_token: 'test')

# Invalid expiration type
session.update_expiration(expiration: "invalid")
# => Familia::Problem: Default expiration must be a number (String given for UserSession)

# Negative expiration
session.update_expiration(expiration: -1)
# => Familia::Problem: Default expiration must be non-negative (-1 given for UserSession)

# Valid expiration
session.update_expiration(expiration: 3600)  # => true
```

### Debug Logging

```ruby
# Enable debug logging to see expiration operations
Familia.debug = true

session = UserSession.new(session_token: 'debug_session')
session.save
session.update_expiration(expiration: 5.minutes)
# Structured logging output:
# TTL updated operation=expire key=user_session:debug_session ttl_seconds=300.0 class=UserSession identifier=debug_session
```

## Debugging and Troubleshooting

### Common Issues

**1. Expiration Not Applied**
```ruby
session = UserSession.new
# ❌ Won't work - object must be saved first
session.update_expiration(expiration: 1.hour)

# ✅ Correct - save first, then expire
session.save
session.update_expiration(expiration: 1.hour)
```

**2. Related Fields Not Expiring**
```ruby
class Customer < Familia::Horreum
  feature :expiration

  field :name
  list :orders  # ❌ Won't cascade - no default_expiration defined
end

# ✅ Fix: Define default_expiration for fields that should cascade
class Customer < Familia::Horreum
  feature :expiration
  default_expiration 1.day

  field :name
  list :orders, default_expiration: 12.hours  # Will cascade
end
```

**3. Inheritance Issues**
```ruby
class BaseModel < Familia::Horreum
  # ❌ Parent doesn't have expiration feature
  default_expiration 1.hour
end

class DerivedModel < BaseModel
  feature :expiration  # ❌ Child has feature but parent doesn't
end

# ✅ Fix: Enable feature on parent class
class BaseModel < Familia::Horreum
  feature :expiration
  default_expiration 1.hour
end
```

**4. No-Op Behavior Without Feature**
```ruby
class BasicModel < Familia::Horreum
  # No expiration feature enabled
  field :data
end

basic = BasicModel.new
basic.update_expiration(expiration: 1.hour)  # No-op, returns nil
basic.ttl                                    # Returns -1
basic.expires?                              # Returns false
basic.expired?                              # Returns false
```

## Testing TTL Behavior

### RSpec Testing

```ruby
RSpec.describe UserSession do
  describe "expiration behavior" do
    let(:session) { described_class.new(session_token: 'test_session') }

    it "inherits class default expiration" do
      expect(session.default_expiration).to eq(described_class.default_expiration)
    end

    it "allows instance-level expiration override" do
      session.default_expiration = 15.minutes
      expect(session.default_expiration).to eq(900.0)
    end

    it "applies TTL to database key" do
      session.save
      session.update_expiration(expiration: 10.minutes)

      ttl = session.ttl
      expect(ttl).to be > 500  # Should be close to 600 seconds
      expect(ttl).to be <= 600
    end

    it "provides TTL status methods" do
      session.save
      session.update_expiration(expiration: 5.minutes)

      expect(session.expires?).to be true
      expect(session.expired?).to be false
      expect(session.expired?(10.minutes)).to be true  # Expiring within 10 minutes
    end

    it "supports expiration extension" do
      session.save
      session.update_expiration(expiration: 5.minutes)

      initial_ttl = session.ttl
      session.extend_expiration(5.minutes)

      expect(session.ttl).to be > initial_ttl
    end

    it "cascades expiration to related fields with default_expiration" do
      session.save
      session.activity_log.push('login')  # Assume activity_log has default_expiration

      session.update_expiration(expiration: 5.minutes)

      # Both main object and related fields should have TTL
      expect(session.ttl).to be > 250
      expect(session.activity_log.ttl).to be > 250
    end
  end
end
```

### Integration Testing

```ruby
# test/integration/session_expiration_test.rb
class SessionExpirationTest < ActionDispatch::IntegrationTest
  test "session extends TTL on activity" do
    # Login and get session
    post '/login', params: { username: 'test', password: 'password' }
    session_token = response.cookies['session_token']

    session = UserSession.find(session_token)
    initial_ttl = session.ttl

    # Wait a bit
    sleep 2

    # Make another request
    get '/dashboard'

    # TTL should be refreshed
    refreshed_ttl = session.ttl
    expect(refreshed_ttl).to be > initial_ttl
  end
end
```

## API Reference

### Instance Methods

#### `update_expiration(expiration: nil)`
Sets TTL for the object and cascades to related fields with `default_expiration`.

**Parameters:**
- `expiration` (Numeric, nil) - TTL in seconds. Uses `default_expiration` if nil.

**Returns:** Boolean indicating success

**Raises:** `Familia::Problem` for invalid expiration values

#### `ttl`
Get remaining TTL for this object.

**Returns:**
- Integer > 0: Seconds remaining
- -1: No TTL set (persistent)
- -2: Key doesn't exist

#### `expires?`
Check if object has TTL set.

**Returns:** Boolean - true if TTL is set

#### `expired?(threshold = 0)`
Check if object is expired or expiring soon.

**Parameters:**
- `threshold` (Numeric) - Consider expired if TTL <= threshold

**Returns:** Boolean - true if expired/expiring

#### `extend_expiration(duration)`
Extend current TTL by additional time.

**Parameters:**
- `duration` (Numeric) - Additional seconds to add

**Returns:** Boolean indicating success

#### `persist!`
Remove TTL, making object persistent.

**Returns:** Boolean indicating success

### Class Methods

#### `default_expiration(num = nil)`
Get/set class-level default expiration.

**Parameters:**
- `num` (Numeric, nil) - Set expiration if provided

**Returns:** Float - current default expiration in seconds

---

## See Also

- **[Technical Reference](../reference/api-technical.md#feature-system)** - Implementation details and advanced patterns
- **[Overview](../overview.md#automatic-expiration)** - Conceptual introduction to expiration
- **[Feature System Guide](feature-system.md)** - Understanding Familia's feature architecture
- **[Implementation Guide](implementation.md)** - Production deployment and configuration patterns

The Expiration feature provides a robust foundation for managing data lifecycle in Familia applications, with flexible configuration options, automatic cascading to related objects, and comprehensive TTL monitoring capabilities.
