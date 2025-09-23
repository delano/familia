# External Identifiers Guide

> **💡 Quick Reference**
>
> Enable integration with external systems and legacy databases:
> ```ruby
> class ExternalUser < Familia::Horreum
>   feature :external_identifier
>   field :internal_id, :external_id, :name, :sync_status
> end
> ```

## Overview

The External Identifier feature provides seamless integration between Familia objects and external systems. Whether you're migrating from a legacy database, integrating with third-party APIs, or maintaining bidirectional synchronization with external services, this feature handles identifier mapping, validation, and sync status tracking.

## Why Use External Identifiers?

**Legacy Integration**: Migrate existing systems while maintaining references to original identifiers.

**API Synchronization**: Keep local objects synchronized with external services using their native identifiers.

**Dual-Key Strategy**: Maintain both internal Familia identifiers and external system identifiers for robust integration.

**Sync Tracking**: Built-in status tracking for synchronization operations and failure handling.

**Validation**: Ensure external identifiers meet format requirements and business rules.

## Quick Start

### Basic External ID Mapping

```ruby
class Customer < Familia::Horreum
  feature :external_identifier

  identifier_field :internal_id
  field :internal_id, :external_id, :name, :email, :sync_status
end

# Create with external mapping
customer = Customer.new(
  internal_id: SecureRandom.uuid,
  external_id: "ext_customer_12345",
  name: "Acme Corporation",
  email: "contact@acme.com"
)
customer.save  # Automatically creates bidirectional mapping

# Find by external ID
found_customer = Customer.find_by_external_id("ext_customer_12345")
puts found_customer.name  # => "Acme Corporation"
```

### Legacy Database Migration

```ruby
class LegacyAccount < Familia::Horreum
  feature :external_identifier, prefix: "legacy"

  identifier_field :familia_id
  field :familia_id, :legacy_account_id, :username, :migration_status

  # External ID validation
  def valid_external_id?
    legacy_account_id.present? &&
    legacy_account_id.match?(/^LAC[A-Z]{2}\d{8}$/)
  end
end

# Migrate legacy data
legacy_user = LegacyAccount.new(
  familia_id: SecureRandom.uuid,
  legacy_account_id: "LACUS12345678",
  username: "john_doe"
)

if legacy_user.valid_external_id?
  legacy_user.save
  legacy_user.mark_migration_completed
end
```

## Configuration Options

### Basic Configuration

```ruby
class ExternalResource < Familia::Horreum
  feature :external_identifier,
          validation_pattern: /^ext_\d{6,}$/,
          source_system: "CustomerAPI",
          bidirectional: true  # Default

  field :resource_id, :external_id, :data
end
```

**Configuration Parameters:**
- `validation_pattern`: Regex pattern for external ID validation
- `source_system`: Name of the external system (for logging/debugging)
- `bidirectional`: Enable bidirectional mapping (default: true)
- `prefix`: Optional prefix for mapping keys

### Advanced Validation

```ruby
class StrictExternalUser < Familia::Horreum
  feature :external_identifier,
          validation_pattern: /^user_[a-z0-9]{8,16}$/,
          source_system: "AuthService"

  field :user_id, :external_id, :username, :permissions

  # Custom validation beyond pattern matching
  def validate_external_id!
    return false unless valid_external_id_format?

    # Check against blacklist
    blacklisted_ids = ["user_test", "user_admin", "user_system"]
    return false if blacklisted_ids.include?(external_id)

    # Verify with external service
    external_service_response = AuthService.verify_user_id(external_id)
    external_service_response['valid'] == true
  end

  private

  def valid_external_id_format?
    external_id.present? && external_id.match?(self.class.validation_pattern)
  end
end
```

## Mapping and Lookup Operations

### Bidirectional Mapping

External identifiers automatically maintain bidirectional mappings for efficient lookups:

```ruby
class Product < Familia::Horreum
  feature :external_identifier
  field :product_id, :external_sku, :name, :price
end

product = Product.create(
  product_id: "familia_prod_123",
  external_sku: "SKU-ABC-789",
  name: "Widget Pro"
)

# Automatic bidirectional mapping is created:
# external_id_mapping["SKU-ABC-789"] = "familia_prod_123"
# internal_id_mapping["familia_prod_123"] = "SKU-ABC-789"

# Fast lookups in both directions
by_external = Product.find_by_external_id("SKU-ABC-789")
by_internal = Product.load("familia_prod_123")

# Both return the same object
by_external.product_id == by_internal.product_id  # => true
```

### Batch Operations

Efficiently handle multiple external identifier operations:

```ruby
class BulkImporter
  def self.import_external_users(external_data_array)
    external_ids = external_data_array.map { |data| data['external_id'] }

    # Batch lookup existing users
    existing_users = ExternalUser.multiget_by_external_ids(external_ids)
    existing_external_ids = existing_users.compact.map(&:external_id)

    # Process only new users
    new_data = external_data_array.reject do |data|
      existing_external_ids.include?(data['external_id'])
    end

    # Batch create new users
    new_users = new_data.map do |data|
      ExternalUser.new(
        internal_id: SecureRandom.uuid,
        external_id: data['external_id'],
        name: data['name'],
        email: data['email']
      )
    end

    # Batch save with transaction
    ExternalUser.transaction do |redis|
      new_users.each(&:save)
    end

    new_users
  end
end
```

## Synchronization Status Tracking

### Built-in Sync Status Management

```ruby
class SyncableResource < Familia::Horreum
  feature :external_identifier

  field :resource_id, :external_id, :data, :sync_status, :last_sync_at, :sync_error

  def sync_to_external!
    mark_sync_pending

    begin
      # Simulate external API call
      response = ExternalAPI.update_resource(external_id, data: self.data)

      if response.success?
        mark_sync_completed
        self.last_sync_at = Familia.now.to_i
        save
      else
        mark_sync_failed(response.error_message)
      end
    rescue => e
      mark_sync_failed(e.message)
      raise
    end
  end

  def sync_from_external!
    mark_sync_pending

    begin
      external_data = ExternalAPI.get_resource(external_id)
      self.data = external_data['data']
      mark_sync_completed
      save
    rescue => e
      mark_sync_failed(e.message)
      raise
    end
  end

  def needs_sync?
    sync_status != 'completed' ||
    (last_sync_at && (Familia.now.to_i - last_sync_at) > 1.hour)
  end
end

# Usage
resource = SyncableResource.find_by_external_id("ext_123")

if resource.needs_sync?
  resource.sync_from_external!
end

puts resource.sync_status  # => "completed", "pending", "failed"
```

### Sync Status Methods

The external identifier feature provides these built-in status methods:

```ruby
# Status management
object.mark_sync_pending
object.mark_sync_completed
object.mark_sync_failed(error_message)

# Status checking
object.sync_pending?        # => true/false
object.sync_completed?      # => true/false
object.sync_failed?         # => true/false

# Error handling
object.sync_error           # => error message if failed
object.clear_sync_error     # Reset error state
```

## Integration Patterns

### API Integration with Webhooks

```ruby
class WebhookHandler
  def self.handle_external_update(webhook_data)
    external_id = webhook_data['resource_id']
    resource = ExternalResource.find_by_external_id(external_id)

    if resource
      # Update existing resource
      resource.data = webhook_data['data']
      resource.mark_sync_completed
      resource.save
    else
      # Create new resource from webhook
      resource = ExternalResource.create(
        internal_id: SecureRandom.uuid,
        external_id: external_id,
        data: webhook_data['data']
      )
      resource.mark_sync_completed
    end

    resource
  end
end

# Webhook endpoint
post '/webhook/external_updates' do
  webhook_data = JSON.parse(request.body.read)
  WebhookHandler.handle_external_update(webhook_data)
  status 200
end
```

### Legacy Database Migration

```ruby
class LegacyMigration
  def self.migrate_customers_from_legacy_db
    # Connect to legacy database
    legacy_db = Sequel.connect(ENV['LEGACY_DATABASE_URL'])

    legacy_db[:customers].each do |legacy_row|
      # Check if already migrated
      existing = Customer.find_by_external_id(legacy_row[:customer_id])
      next if existing

      # Create new Familia object
      customer = Customer.new(
        internal_id: SecureRandom.uuid,
        external_id: legacy_row[:customer_id].to_s,
        name: legacy_row[:company_name],
        email: legacy_row[:email],
        created_at: legacy_row[:created_at].to_i
      )

      if customer.valid_external_id?
        customer.save
        customer.mark_migration_completed
        puts "Migrated customer: #{customer.external_id}"
      else
        puts "Invalid external ID: #{legacy_row[:customer_id]}"
      end
    end
  end
end
```

### Multi-System Integration

```ruby
class MultiSystemResource < Familia::Horreum
  feature :external_identifier

  field :internal_id, :crm_id, :billing_id, :support_id, :name

  # Multiple external system mappings
  def crm_mapping
    @crm_mapping ||= ExternalIdMapping.new(self, :crm_id, "CRM_System")
  end

  def billing_mapping
    @billing_mapping ||= ExternalIdMapping.new(self, :billing_id, "Billing_System")
  end

  def support_mapping
    @support_mapping ||= ExternalIdMapping.new(self, :support_id, "Support_System")
  end

  def sync_to_all_systems!
    [crm_mapping, billing_mapping, support_mapping].each do |mapping|
      mapping.sync_to_external!
    end
  end

  class ExternalIdMapping
    def initialize(resource, id_field, system_name)
      @resource = resource
      @id_field = id_field
      @system_name = system_name
    end

    def sync_to_external!
      external_id = @resource.send(@id_field)
      return unless external_id

      case @system_name
      when "CRM_System"
        CRMApi.update_contact(external_id, @resource.to_crm_format)
      when "Billing_System"
        BillingApi.update_customer(external_id, @resource.to_billing_format)
      when "Support_System"
        SupportApi.update_user(external_id, @resource.to_support_format)
      end
    end
  end
end
```

## Performance Considerations

### Efficient Batch Lookups

```ruby
# Instead of individual lookups
external_ids = ["ext_1", "ext_2", "ext_3"]
users = external_ids.map { |id| User.find_by_external_id(id) }

# Use batch operations
users = User.multiget_by_external_ids(external_ids)
```

### Caching Strategies

```ruby
class CachedExternalResource < Familia::Horreum
  feature :external_identifier

  # Cache external ID mappings
  def self.find_by_external_id_cached(external_id)
    cache_key = "external_id_mapping:#{external_id}"

    cached_internal_id = Familia.redis.get(cache_key)
    if cached_internal_id
      return load(cached_internal_id)
    end

    # Fallback to database lookup
    resource = find_by_external_id(external_id)
    if resource
      Familia.redis.setex(cache_key, 300, resource.identifier)
    end

    resource
  end
end
```

### Index Optimization

```ruby
class OptimizedExternalResource < Familia::Horreum
  feature :external_identifier

  # Use dedicated sorted sets for each status with timestamp scores
  sorted_set :pending_sync_resources,
             score: ->(obj) { obj.last_sync_at&.to_i || 0 }
  sorted_set :completed_sync_resources,
             score: ->(obj) { obj.last_sync_at&.to_i || 0 }
  sorted_set :failed_sync_resources,
             score: ->(obj) { obj.last_sync_at&.to_i || 0 }

  def self.pending_sync_resources(limit: 100)
    # Query resources that need syncing, ordered by oldest first
    pending_sync_resources.range(0, limit - 1).map { |id| load(id) }.compact
  end

  def self.recently_synced(status:, limit: 100)
    # Get recently synced resources by status, newest first
    case status.to_s
    when 'pending'
      pending_sync_resources.revrange(0, limit - 1).map { |id| load(id) }.compact
    when 'completed'
      completed_sync_resources.revrange(0, limit - 1).map { |id| load(id) }.compact
    when 'failed'
      failed_sync_resources.revrange(0, limit - 1).map { |id| load(id) }.compact
    else
      []
    end
  end
end
```

## Testing Strategies

### Test External ID Integration

```ruby
# test/models/external_user_test.rb
require 'test_helper'

class ExternalUserTest < Minitest::Test
  def test_bidirectional_mapping
    user = ExternalUser.create(
      internal_id: "test_123",
      external_id: "ext_456",
      name: "Test User"
    )

    # Test lookup by external ID
    found_by_external = ExternalUser.find_by_external_id("ext_456")
    assert_equal user.internal_id, found_by_external.internal_id

    # Test lookup by internal ID
    found_by_internal = ExternalUser.load("test_123")
    assert_equal user.external_id, found_by_internal.external_id
  end

  def test_sync_status_tracking
    user = ExternalUser.create(
      internal_id: "test_123",
      external_id: "ext_456",
      name: "Test User"
    )

    # Test status transitions
    user.mark_sync_pending
    assert user.sync_pending?
    refute user.sync_completed?

    user.mark_sync_completed
    assert user.sync_completed?
    refute user.sync_pending?

    user.mark_sync_failed("Network error")
    assert user.sync_failed?
    assert_equal "Network error", user.sync_error
  end

  def test_external_id_validation
    user = StrictExternalUser.new(
      user_id: "test_123",
      external_id: "invalid_format"
    )

    refute user.valid_external_id_format?

    user.external_id = "user_validformat123"
    assert user.valid_external_id_format?
  end
end
```

### Mock External Services

```ruby
# test/support/external_service_mock.rb
class ExternalServiceMock
  def self.setup_mocks
    # Mock successful API responses
    stub_request(:get, /external-api\.com\/resource\/ext_\d+/)
      .to_return(
        status: 200,
        body: { data: "mocked_data", updated_at: Time.now.iso8601 }.to_json
      )

    stub_request(:post, /external-api\.com\/resource/)
      .to_return(
        status: 201,
        body: { id: "ext_#{rand(1000)}", status: "created" }.to_json
      )
  end

  def self.setup_error_mocks
    # Mock API errors for testing error handling
    stub_request(:get, /external-api\.com\/resource\/ext_error/)
      .to_return(status: 500, body: "Internal Server Error")
  end
end
```

## Troubleshooting

### Common Issues

**External ID Not Found**
```ruby
# Debug external ID mappings
puts ExternalUser.external_id_mapping.hgetall
# Shows all external_id -> internal_id mappings

# Check reverse mapping
puts ExternalUser.internal_id_mapping.hgetall
# Shows all internal_id -> external_id mappings
```

**Sync Status Issues**
```ruby
# Check sync status for all objects of a type
ExternalUser.all.each do |user|
  puts "#{user.external_id}: #{user.sync_status} (#{user.sync_error})"
end

# Reset failed sync statuses
ExternalUser.all.select(&:sync_failed?).each(&:clear_sync_error)
```

**Validation Failures**
```ruby
user = ExternalUser.new(external_id: "invalid")

unless user.valid_external_id?
  puts "Validation failed for: #{user.external_id}"
  puts "Expected pattern: #{ExternalUser.validation_pattern}"
end
```

### Performance Debugging

```ruby
# Monitor external ID lookup performance
def benchmark_external_lookups(external_ids)
  require 'benchmark'

  Benchmark.bm(20) do |x|
    x.report("Individual lookups:") do
      external_ids.each { |id| ExternalUser.find_by_external_id(id) }
    end

    x.report("Batch lookups:") do
      ExternalUser.multiget_by_external_ids(external_ids)
    end
  end
end

# Check mapping Valkey/Redis key sizes
mapping_keys = Familia.redis.keys("*external_id_mapping*")
mapping_keys.each do |key|
  size = Familia.redis.hlen(key)
  puts "#{key}: #{size} mappings"
end
```

---

## See Also

- **[Technical Reference](../reference/api-technical.md#external-identifier-feature-v200-pre7)** - Implementation details and advanced patterns
- **[Object Identifiers Guide](feature-object-identifiers.md)** - Automatic ID generation strategies
- **[Feature System Guide](feature-system.md)** - Understanding the feature architecture
- **[Implementation Guide](implementation.md)** - Advanced configuration and migration patterns
