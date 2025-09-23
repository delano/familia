# Feature System Guide

## Overview

Familia's feature system provides a modular architecture for extending Horreum classes with reusable functionality. Features are self-contained modules that can be mixed into classes with dependency management, conflict resolution, and automatic registration.

## Core Concepts

### Feature Architecture

The feature system consists of several key components:

1. **Feature Modules**: Self-contained functionality modules
2. **Registration System**: Automatic feature discovery and registration
3. **Dependency Management**: Explicit feature dependencies
4. **Conflict Resolution**: Handling method name conflicts
5. **Category-based Fields**: Special field types for different purposes

### Feature Lifecycle

```ruby
# 1. Feature definition and registration (automatic)
class MyFeature
  def self.included(base)
    base.extend ClassMethods
    base.prepend InstanceMethods
  end

  # Self-register with Familia
  Familia::Base.add_feature self, :my_feature, depends_on: [:other_feature]
end

# 2. Feature activation in classes
class Customer < Familia::Horreum
  feature :my_feature  # Validates, checks dependencies, includes module
end

# 3. Runtime usage
customer = Customer.new
customer.my_feature_method  # Available after feature inclusion
```

## Built-in Features

### Core Features

#### Expiration
```ruby
class Session < Familia::Horreum
  feature :expiration
  default_expiration 1.hour

  field :user_id, :data
end

session = Session.new(user_id: 123)
session.update_expiration(30.minutes)  # Custom TTL
session.ttl                            # Check remaining time
```

#### SafeDump
```ruby
class Customer < Familia::Horreum
  feature :safe_dump

  field :name, :email
  field :ssn        # Sensitive field
  field :password   # Sensitive field

  # Whitelist fields for API responses
  safe_dump_fields :name, :email  # Excludes ssn, password
end

customer.safe_dump  # => { name: "John", email: "john@example.com" }
customer.dump       # => { name: "John", email: "john@example.com", ssn: "123-45-6789", password: "secret" }
```

#### Encrypted Fields
```ruby
class Vault < Familia::Horreum
  feature :encrypted_fields

  field :name                    # Regular field
  encrypted_field :secret_key    # Encrypted storage
  encrypted_field :api_token     # Another encrypted field
end

vault = Vault.new(secret_key: "super-secret")
vault.save
# secret_key is encrypted in Redis, decrypted on access
```

#### Transient Fields
```ruby
class ApiClient < Familia::Horreum
  feature :transient_fields

  field :endpoint               # Persistent field
  transient_field :auth_token   # Runtime only, RedactedString
end

client = ApiClient.new(auth_token: ENV['API_TOKEN'])
client.auth_token.expose { |token| make_api_call(token) }
client.auth_token.clear!  # Explicit cleanup
```

#### Relationships
```ruby
class Customer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid, :name, :email

  # Define relationship collections
  participates_in :active_users, type: :sorted_set
  indexed_by :email_lookup, field: :email
  set :domains
end

class Domain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id, :name

  # Declare membership in customer collections
  participates_in Customer, :domains, type: :set
end

# Usage
customer = Customer.new(custid: "cust123", name: "Acme Corp")
domain = Domain.new(domain_id: "dom456", name: "acme.com")

# Establish bidirectional relationships
domain.add_to_customer_domains(customer.custid)
customer.domains.add(domain.identifier)

# Query relationships
domain.in_customer_domains?(customer.custid)  # => true
```

#### Quantization
```ruby
class Metric < Familia::Horreum
  feature :quantization

  field :value
  quantized_field :hourly_stats, interval: 1.hour
  quantized_field :daily_stats, interval: 1.day
end

# Automatically buckets data by time intervals
metric = Metric.new(value: 42)
metric.hourly_stats   # Bucketed by hour
metric.daily_stats    # Bucketed by day
```

## Creating Custom Features

### Basic Feature Structure

```ruby
module Familia
  module Features
    module MyCustomFeature
      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods
        base.prepend InstanceMethods  # Use prepend for method interception
      end

      module ClassMethods
        def custom_class_method
          "Available on #{self} class"
        end
      end

      module InstanceMethods
        def custom_instance_method
          "Available on #{self.class} instances"
        end

        # Intercept field access (if needed)
        def field_value=(value)
          # Custom processing before field assignment
          processed_value = process_value(value)
          super(processed_value)  # Call original field setter
        end
      end

      # Register the feature
      Familia::Base.add_feature self, :my_custom_feature
    end
  end
end
```

### Advanced Feature with Dependencies

```ruby
module Familia
  module Features
    module AdvancedAudit
      def self.included(base)
        base.extend ClassMethods
        base.prepend InstanceMethods

        # Initialize audit tracking
        base.class_list :audit_log
        base.class_hashkey :field_history
      end

      module ClassMethods
        def enable_audit_for(*field_names)
          @audited_fields ||= ::Set.new
          @audited_fields.merge(field_names.map(&:to_sym))
        end

        def audited_fields
          @audited_fields || ::Set.new
        end
      end

      module InstanceMethods
        def save
          # Audit before saving
          audit_changes if respond_to?(:audit_changes)
          super
        end

        private

        def audit_changes
          self.class.audited_fields.each do |field|
            if instance_variable_changed?(field)
              record_field_change(field)
            end
          end
        end

        def record_field_change(field)
          change_record = {
            field: field,
            old_value: instance_variable_was(field),
            new_value: instance_variable_get("@#{field}"),
            timestamp: Time.now.to_f
          }

          self.class.audit_log.append(change_record.to_json)
        end
      end

      # Register with dependency on safe_dump
      Familia::Base.add_feature self, :advanced_audit, depends_on: [:safe_dump]
    end
  end
end

# Usage
class Customer < Familia::Horreum
  feature :safe_dump      # Dependency satisfied first
  feature :advanced_audit # Now can be loaded

  enable_audit_for :name, :email, :status

  field :name, :email, :status, :created_at
end
```

### Feature with Custom Field Types

```ruby
module Familia
  module Features
    module TimestampTracking
      def self.included(base)
        base.extend ClassMethods

        # Add timestamp fields automatically
        base.timestamp_field :created_at
        base.timestamp_field :updated_at
      end

      module ClassMethods
        def timestamp_field(name, auto_update: true)
          # Create custom field type for timestamps
          require_relative '../field_types/timestamp_field_type'

          field_type = TimestampFieldType.new(
            name,
            auto_update: auto_update,
            format: :iso8601
          )
          register_field_type(field_type)
        end
      end

      # Register feature
      Familia::Base.add_feature self, :timestamp_tracking
    end
  end
end

# Custom field type (separate file)
class TimestampFieldType < Familia::FieldType
  def initialize(name, auto_update: true, format: :unix, **options)
    super(name, **options)
    @auto_update = auto_update
    @format = format
  end

  def serialize_value(record, value)
    case @format
    when :unix then value&.to_f
    when :iso8601 then value&.iso8601
    else value&.to_s
    end
  end

  def deserialize_value(record, stored_value)
    return nil if stored_value.nil?

    case @format
    when :unix then Time.at(stored_value.to_f)
    when :iso8601 then Time.parse(stored_value)
    else Time.parse(stored_value)
    end
  end
end
```

## Feature Dependencies

### Declaring Dependencies

```ruby
# Feature with dependencies
Familia::Base.add_feature MyFeature, :my_feature, depends_on: [:safe_dump, :expiration]

# Will verify dependencies when feature is activated:
class Model < Familia::Horreum
  feature :safe_dump    # Must be loaded first
  feature :expiration   # Must be loaded first
  feature :my_feature   # Dependencies satisfied
end
```

### Dependency Validation

```ruby
# This will raise an error:
class BadModel < Familia::Horreum
  feature :my_feature  # Error: requires safe_dump, expiration
end
# => Familia::Problem: my_feature requires: safe_dump, expiration

# Correct order:
class GoodModel < Familia::Horreum
  feature :safe_dump
  feature :expiration
  feature :my_feature  # ✅ Dependencies satisfied
end
```

## Method Conflict Resolution

### Conflict Detection

```ruby
class Customer < Familia::Horreum
  field :status  # Defines status= and status methods

  # This would conflict with field-generated method
  def status
    "custom implementation"  # ⚠️ Potential conflict
  end
end
```

### Conflict Resolution Strategies

```ruby
# 1. Raise on conflict (default)
field :name, on_conflict: :raise     # Raises if method exists

# 2. Skip definition if conflict
field :name, on_conflict: :skip      # Skips if method exists

# 3. Warn but proceed
field :name, on_conflict: :warn      # Warns but defines method

# 4. Ignore silently
field :name, on_conflict: :ignore    # Proceeds without warning
```

### Using Prepend for Method Interception

```ruby
module MyFeature
  def self.included(base)
    # Use prepend to intercept method calls
    base.prepend InstanceMethods
  end

  module InstanceMethods
    def save
      # Pre-processing
      validate_before_save

      # Call original save method
      result = super

      # Post-processing
      notify_after_save

      result
    end
  end
end
```

## Feature Categories and Field Types

### Field Categories

```ruby
class Document < Familia::Horreum
  field :title                           # Regular field
  field :content, category: :encrypted   # Encrypted field
  field :api_key, category: :transient   # Transient field
  field :tags, category: :indexed        # Custom category
end
```

### Category-based Processing

```ruby
# Features can process fields by category
module IndexingFeature
  def self.included(base)
    base.extend ClassMethods

    # Process all :indexed category fields
    base.field_definitions.select { |f| f.category == :indexed }.each do |field|
      create_index_for(field.name)
    end
  end
end
```

## Feature Discovery and Loading

### Automatic Loading

Features are automatically loaded from the `lib/familia/features/` directory:

```ruby
# lib/familia/features.rb automatically loads:
features_dir = File.join(__dir__, 'features')
Dir.glob(File.join(features_dir, '*.rb')).each do |feature_file|
  require_relative feature_file
end
```

### Manual Feature Registration

```ruby
# For features outside the standard directory
class ExternalFeature
  # Feature implementation...
end

# Register manually
Familia::Base.add_feature ExternalFeature, :external_feature, depends_on: []
```

## Advanced Usage Patterns

### Feature Composition

```ruby
class AdvancedModel < Familia::Horreum
  # Combine multiple features for rich functionality
  feature :expiration      # TTL support
  feature :safe_dump       # API-safe serialization
  feature :encrypted_fields # Secure storage
  feature :quantization    # Time-based bucketing
  feature :transient_fields # Runtime secrets

  # Now has capabilities from all features
  field :name
  encrypted_field :api_key
  transient_field :session_token
  quantized_field :metrics, interval: 1.hour

  default_expiration 24.hours
  safe_dump_fields :name, :created_at
end
```

### Conditional Feature Loading

```ruby
class ConfigurableModel < Familia::Horreum
  # Load features based on configuration
  if Rails.env.production?
    feature :encrypted_fields
    feature :advanced_audit
  end

  if defined?(Sidekiq)
    feature :background_processing
  end

  feature :safe_dump  # Always load
end
```

## Testing Features

### Feature Testing

```ruby
RSpec.describe MyCustomFeature do
  let(:test_class) do
    Class.new(Familia::Horreum) do
      feature :my_custom_feature
      field :name
    end
  end

  it "includes feature methods" do
    instance = test_class.new
    expect(instance).to respond_to(:custom_instance_method)
    expect(test_class).to respond_to(:custom_class_method)
  end

  it "validates dependencies" do
    expect {
      Class.new(Familia::Horreum) do
        feature :advanced_audit  # Missing safe_dump dependency
      end
    }.to raise_error(Familia::Problem, /requires.*safe_dump/)
  end
end
```

### Integration Testing

```ruby
RSpec.describe "Feature Integration" do
  it "combines features correctly" do
    combined_class = Class.new(Familia::Horreum) do
      feature :safe_dump
      feature :expiration
      feature :encrypted_fields

      field :name
      encrypted_field :secret
      safe_dump_fields :name
      default_expiration 1.hour
    end

    instance = combined_class.new(name: "test", secret: "hidden")

    # All features work together
    expect(instance.safe_dump).to eq(name: "test")
    expect(instance.secret).to eq("hidden")  # Decrypted
    expect(instance.ttl).to be > 0           # Has expiration
  end
end
```

## Best Practices

### Feature Design

1. **Single Responsibility**: Each feature should have one clear purpose
2. **Minimal Dependencies**: Avoid complex dependency chains
3. **Graceful Degradation**: Handle missing dependencies gracefully
4. **Clear Naming**: Use descriptive feature and method names
5. **Documentation**: Document feature capabilities and usage

### Method Organization

```ruby
module MyFeature
  def self.included(base)
    base.extend ClassMethods
    base.prepend InstanceMethods  # For interception
    base.include HelperMethods    # For additional utilities
  end

  module ClassMethods
    # Class-level functionality
  end

  module InstanceMethods
    # Instance method interception/override
  end

  module HelperMethods
    # Additional utility methods
  end
end
```

### Performance Considerations

1. **Lazy Loading**: Initialize expensive resources only when needed
2. **Caching**: Cache computed values appropriately
3. **Method Interception**: Use prepend sparingly for performance-critical methods
4. **Field Processing**: Minimize overhead in field serialization/deserialization

The feature system provides a powerful foundation for extending Familia with reusable, composable functionality while maintaining clean separation of concerns and explicit dependency management.
