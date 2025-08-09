# Field System Guide

## Overview

Familia's Field System provides a flexible, extensible architecture for defining and managing object attributes with customizable behavior, conflict resolution, and serialization. The system uses a FieldType-based architecture that separates field definition from implementation, enabling custom field behaviors and advanced features.

## Core Architecture

### FieldType System

The Field System is built around the `FieldType` class hierarchy:

```ruby
FieldType                    # Base class for all field types
├── TransientFieldType      # Non-persistent fields (memory only)
├── EncryptedFieldType      # Encrypted storage fields
└── Custom field types      # User-defined field behaviors
```

### Field Definition Flow

1. **Field Declaration**: `field :name, options...`
2. **FieldType Creation**: Appropriate FieldType instance created
3. **Registration**: FieldType registered with the class
4. **Method Installation**: Getter, setter, and fast methods defined
5. **Runtime Usage**: Methods available on instances

## Basic Usage

### Simple Field Definition

```ruby
class Customer < Familia::Horreum
  # Basic field with default settings
  field :name

  # Field with custom method name
  field :email_address, as: :email

  # Field without accessor methods
  field :internal_data, as: false

  # Field without fast writer method
  field :readonly_data, fast_method: false
end

customer = Customer.new
customer.name = "Acme Corp"           # Standard setter
customer.email = "admin@acme.com"     # Custom method name
customer.name!("Updated Corp")        # Fast writer (immediate DB persistence)
```

### Field Categories

Fields can be categorized for special processing by features:

```ruby
class Document < Familia::Horreum
  field :title                           # Regular field
  field :content, category: :encrypted   # Will be processed by encrypted_fields feature
  field :api_key, category: :transient   # Non-persistent field
  field :tags, category: :indexed        # Custom category for indexing
  field :metadata, category: :json       # Custom JSON serialization
end
```

### Method Conflict Resolution

The Field System provides multiple strategies for handling method name conflicts:

```ruby
class Customer < Familia::Horreum
  # Raise error if method exists (default)
  field :status, on_conflict: :raise

  # Skip field definition if method exists
  field :type, on_conflict: :skip

  # Warn but proceed with definition
  field :class, on_conflict: :warn

  # Silently overwrite existing method
  field :id, on_conflict: :overwrite
end
```

## Advanced Field Types

### Creating Custom Field Types

```ruby
# Custom field type for timestamps
class TimestampFieldType < Familia::FieldType
  def category
    :timestamp
  end

  def define_setter(klass)
    field_name = @name
    method_name = @method_name

    handle_method_conflict(klass, :"#{method_name}=") do
      klass.define_method :"#{method_name}=" do |value|
        # Convert various formats to Unix timestamp
        timestamp = case value
                   when Time then value.to_i
                   when String then Time.parse(value).to_i
                   when Numeric then value.to_i
                   else raise ArgumentError, "Invalid timestamp: #{value}"
                   end
        instance_variable_set(:"@#{field_name}", timestamp)
      end
    end
  end

  def define_getter(klass)
    field_name = @name
    method_name = @method_name

    handle_method_conflict(klass, method_name) do
      klass.define_method method_name do
        timestamp = instance_variable_get(:"@#{field_name}")
        timestamp ? Time.at(timestamp) : nil
      end
    end
  end

  def serialize(value, _record = nil)
    value.respond_to?(:to_i) ? value.to_i : value
  end

  def deserialize(value, _record = nil)
    value ? Time.at(value.to_i) : nil
  end
end

# Register and use the custom field type
class Event < Familia::Horreum
  def self.timestamp_field(name, **options)
    field_type = TimestampFieldType.new(name, **options)
    register_field_type(field_type)
  end

  identifier_field :event_id
  field :event_id, :name, :description
  timestamp_field :created_at
  timestamp_field :updated_at
end

# Usage
event = Event.new(event_id: 'evt_123')
event.created_at = "2023-06-15 14:30:00"  # String input
puts event.created_at.class               # => Time
puts event.created_at                     # => 2023-06-15 14:30:00 UTC
```

### JSON Field Type

```ruby
class JsonFieldType < Familia::FieldType
  def category
    :json
  end

  def define_setter(klass)
    field_name = @name
    method_name = @method_name

    handle_method_conflict(klass, :"#{method_name}=") do
      klass.define_method :"#{method_name}=" do |value|
        # Store as parsed JSON for manipulation
        parsed_value = case value
                      when String then JSON.parse(value)
                      when Hash, Array then value
                      else raise ArgumentError, "Value must be JSON string, Hash, or Array"
                      end
        instance_variable_set(:"@#{field_name}", parsed_value)
      end
    end
  end

  def serialize(value, _record = nil)
    value.to_json if value
  end

  def deserialize(value, _record = nil)
    value ? JSON.parse(value) : nil
  end
end

class Configuration < Familia::Horreum
  def self.json_field(name, **options)
    field_type = JsonFieldType.new(name, **options)
    register_field_type(field_type)
  end

  identifier_field :config_id
  field :config_id, :name
  json_field :settings
  json_field :metadata
end

# Usage
config = Configuration.new(config_id: 'app_config')
config.settings = { theme: 'dark', notifications: true }
config.settings['api_timeout'] = 30

# Automatically serialized to JSON in database
config.save
# Database stores: {"theme":"dark","notifications":true,"api_timeout":30}
```

### Enum Field Type

```ruby
class EnumFieldType < Familia::FieldType
  def initialize(name, values:, **options)
    super(name, **options)
    @valid_values = values.map(&:to_s).to_set
    @default_value = values.first
  end

  def category
    :enum
  end

  def define_setter(klass)
    field_name = @name
    method_name = @method_name
    valid_values = @valid_values

    handle_method_conflict(klass, :"#{method_name}=") do
      klass.define_method :"#{method_name}=" do |value|
        value_str = value.to_s
        unless valid_values.include?(value_str)
          raise ArgumentError, "Invalid #{field_name}: #{value}. Valid values: #{valid_values.to_a.join(', ')}"
        end
        instance_variable_set(:"@#{field_name}", value_str)
      end
    end
  end

  # Add predicate methods for each enum value
  def install(klass)
    super(klass)

    @valid_values.each do |value|
      predicate_method = :"#{@method_name}_#{value}?"
      field_name = @name

      klass.define_method predicate_method do
        instance_variable_get(:"@#{field_name}") == value
      end
    end
  end
end

class Order < Familia::Horreum
  def self.enum_field(name, values:, **options)
    field_type = EnumFieldType.new(name, values: values, **options)
    register_field_type(field_type)
  end

  identifier_field :order_id
  field :order_id, :customer_id
  enum_field :status, values: [:pending, :processing, :shipped, :delivered, :cancelled]
  enum_field :priority, values: [:low, :normal, :high, :urgent]
end

# Usage
order = Order.new(order_id: 'ord_123')
order.status = :pending
order.priority = 'high'

# Predicate methods automatically available
order.status_pending?    # => true
order.status_shipped?    # => false
order.priority_high?     # => true
order.priority_urgent?   # => false
```

## Field Metadata and Introspection

### Accessing Field Information

```ruby
class Product < Familia::Horreum
  field :name, category: :searchable
  field :price, category: :numeric
  field :description, category: :text
  field :secret_key, category: :encrypted
  transient_field :temp_data
end

# Get all field names
Product.fields
# => [:name, :price, :description, :secret_key, :temp_data]

# Get field types registry
Product.field_types
# => { name: #<FieldType...>, price: #<FieldType...>, ... }

# Get fields by category
Product.fields.select { |f| Product.field_types[f].category == :searchable }
# => [:name]

# Get persistent vs transient fields
Product.persistent_fields  # => [:name, :price, :description, :secret_key]
Product.transient_fields   # => [:temp_data]

# Field method mapping (for backward compatibility)
Product.field_method_map
# => { name: :name, price: :price, secret_key: :secret_key, temp_data: :temp_data }
```

### Field Categories for Feature Processing

```ruby
# Features can process fields by category
module SearchableFieldsFeature
  def self.included(base)
    base.extend ClassMethods

    # Process all searchable fields
    searchable_fields = base.fields.select do |field|
      base.field_types[field].category == :searchable
    end

    searchable_fields.each do |field|
      create_search_index_for(base, field)
    end
  end

  module ClassMethods
    def search_by_field(field_name, query)
      # Implementation for field-specific search
    end
  end

  private

  def self.create_search_index_for(klass, field_name)
    # Create search index methods
    klass.define_singleton_method :"search_by_#{field_name}" do |query|
      # Search implementation
    end
  end
end

class Product < Familia::Horreum
  feature :searchable_fields  # Processes all :searchable category fields

  field :name, category: :searchable
  field :description, category: :searchable
  field :internal_id, category: :system
end

# Auto-generated search methods available
Product.search_by_name("laptop")
Product.search_by_description("gaming")
```

## Fast Methods and Database Operations

### Fast Method Behavior

Fast methods provide immediate database persistence without affecting other object state:

```ruby
class UserProfile < Familia::Horreum
  identifier_field :user_id
  field :user_id, :name, :email, :last_login_at
end

profile = UserProfile.new(user_id: 'user_123')
profile.save

# Regular setter: updates instance variable only
profile.last_login_at = Time.now  # Not yet in database

# Fast method: immediate database write
profile.last_login_at!(Time.now)  # Written to database immediately

# Reading from database
profile.last_login_at   # => reads from instance variable
profile.last_login_at!  # => reads directly from database
```

### Custom Fast Method Behavior

```ruby
class AuditedFieldType < Familia::FieldType
  def define_fast_writer(klass)
    return unless @fast_method_name

    field_name = @name
    method_name = @method_name
    fast_method_name = @fast_method_name

    handle_method_conflict(klass, fast_method_name) do
      klass.define_method fast_method_name do |*args|
        if args.empty?
          # Read from database
          hget(field_name)
        else
          # Write to database with audit trail
          value = args.first
          old_value = hget(field_name)

          # Update the field
          prepared = serialize_value(value)
          send(:"#{method_name}=", value) if method_name
          result = hset(field_name, prepared)

          # Create audit entry
          audit_entry = {
            field: field_name,
            old_value: old_value,
            new_value: value,
            changed_at: Time.now.to_f,
            changed_by: Thread.current[:current_user]&.id
          }

          # Store audit trail
          audit_key = "#{dbkey}:audit"
          Familia.dbclient.lpush(audit_key, audit_entry.to_json)
          Familia.dbclient.ltrim(audit_key, 0, 99)  # Keep last 100 changes

          result
        end
      end
    end
  end
end

class AuditedDocument < Familia::Horreum
  def self.audited_field(name, **options)
    field_type = AuditedFieldType.new(name, **options)
    register_field_type(field_type)
  end

  identifier_field :doc_id
  field :doc_id, :title
  audited_field :content
  audited_field :status
end

# Usage creates audit trail
doc = AuditedDocument.new(doc_id: 'doc_123')
doc.save

Thread.current[:current_user] = OpenStruct.new(id: 'user_456')
doc.content!("Initial content")    # Audited change
doc.status!("draft")               # Audited change

# View audit trail
audit_key = "#{doc.dbkey}:audit"
audit_entries = Familia.dbclient.lrange(audit_key, 0, -1)
audit_entries.map { |entry| JSON.parse(entry) }
```

## Integration Patterns

### Rails Integration

```ruby
# app/models/concerns/familia_fields.rb
module FamiliaFields
  extend ActiveSupport::Concern

  class_methods do
    # Rails-style field definitions
    def string_field(name, **options)
      field(name, **options)
    end

    def integer_field(name, **options)
      field_type = Class.new(Familia::FieldType) do
        def serialize(value, _record = nil)
          value.to_i if value
        end

        def deserialize(value, _record = nil)
          value.to_i if value
        end
      end

      register_field_type(field_type.new(name, **options))
    end

    def boolean_field(name, **options)
      field_type = Class.new(Familia::FieldType) do
        def serialize(value, _record = nil)
          !!value
        end

        def deserialize(value, _record = nil)
          value == true || value == 'true' || value == '1'
        end

        def define_getter(klass)
          super(klass)

          # Add predicate method
          predicate_method = :"#{@method_name}?"
          field_name = @name

          klass.define_method predicate_method do
            !!instance_variable_get(:"@#{field_name}")
          end
        end
      end

      register_field_type(field_type.new(name, **options))
    end
  end
end

class User < Familia::Horreum
  include FamiliaFields

  identifier_field :user_id
  string_field :user_id, :email, :name
  integer_field :age, :login_count
  boolean_field :active, :verified
end

user = User.new(user_id: 'user_123')
user.age = "25"          # Automatically converted to integer
user.active = "true"     # Automatically converted to boolean
user.verified?           # => false (predicate method)
```

### Validation Integration

```ruby
class ValidatedFieldType < Familia::FieldType
  def initialize(name, validations: {}, **options)
    super(name, **options)
    @validations = validations
  end

  def define_setter(klass)
    field_name = @name
    method_name = @method_name
    validations = @validations

    handle_method_conflict(klass, :"#{method_name}=") do
      klass.define_method :"#{method_name}=" do |value|
        # Run validations
        validations.each do |validator, constraint|
          case validator
          when :presence
            if constraint && (value.nil? || value.to_s.strip.empty?)
              raise ArgumentError, "#{field_name} cannot be blank"
            end
          when :length
            if constraint.is_a?(Hash) && constraint[:minimum]
              if value.to_s.length < constraint[:minimum]
                raise ArgumentError, "#{field_name} is too short (minimum #{constraint[:minimum]} characters)"
              end
            end
          when :format
            if constraint.is_a?(Regexp) && !value.to_s.match?(constraint)
              raise ArgumentError, "#{field_name} format is invalid"
            end
          when :inclusion
            if constraint.is_a?(Array) && !constraint.include?(value)
              raise ArgumentError, "#{field_name} must be one of: #{constraint.join(', ')}"
            end
          end
        end

        instance_variable_set(:"@#{field_name}", value)
      end
    end
  end
end

class User < Familia::Horreum
  def self.validated_field(name, validations: {}, **options)
    field_type = ValidatedFieldType.new(name, validations: validations, **options)
    register_field_type(field_type)
  end

  identifier_field :user_id
  validated_field :user_id, validations: { presence: true }
  validated_field :email, validations: {
    presence: true,
    format: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  }
  validated_field :status, validations: {
    inclusion: %w[active inactive suspended]
  }
  validated_field :name, validations: {
    presence: true,
    length: { minimum: 2 }
  }
end

# Usage with validation
user = User.new
user.email = "invalid-email"     # Raises ArgumentError
user.status = "unknown"          # Raises ArgumentError
user.name = "A"                  # Raises ArgumentError (too short)
```

## Performance Considerations

### Efficient Field Operations

```ruby
class OptimizedFieldAccess < Familia::Horreum
  # Cache field type lookups
  def self.field_type_for(field_name)
    @field_type_cache ||= {}
    @field_type_cache[field_name] ||= field_types[field_name]
  end

  # Batch field updates
  def batch_update(field_values)
    # Update instance variables
    field_values.each do |field, value|
      setter_method = :"#{field}="
      send(setter_method, value) if respond_to?(setter_method)
    end

    # Single database call for persistence
    serialized_values = field_values.transform_values do |value|
      serialize_value(value)
    end

    hmset(serialized_values)
  end

  # Lazy field loading
  def lazy_load_field(field_name)
    return instance_variable_get(:"@#{field_name}") if instance_variable_defined?(:"@#{field_name}")

    value = hget(field_name)
    field_type = self.class.field_type_for(field_name)
    deserialized = field_type&.deserialize(value, self) || value

    instance_variable_set(:"@#{field_name}", deserialized)
    deserialized
  end
end
```

### Memory-Efficient Field Storage

```ruby
class CompactFieldType < Familia::FieldType
  def serialize(value, _record = nil)
    case value
    when String
      # Compress strings longer than 100 characters
      if value.length > 100
        Base64.encode64(Zlib::Deflate.deflate(value))
      else
        value
      end
    else
      value
    end
  end

  def deserialize(value, _record = nil)
    return value unless value.is_a?(String)

    # Check if it's base64 encoded compressed data
    if value.length > 100 && value.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
      begin
        Zlib::Inflate.inflate(Base64.decode64(value))
      rescue
        value  # Return as-is if decompression fails
      end
    else
      value
    end
  end
end
```

## Testing Field Types

### RSpec Testing

```ruby
RSpec.describe TimestampFieldType do
  let(:field_type) { described_class.new(:created_at) }
  let(:test_class) do
    Class.new(Familia::Horreum) do
      def self.name; 'TestClass'; end
    end
  end

  before do
    field_type.install(test_class)
  end

  it "converts various time formats" do
    instance = test_class.new

    instance.created_at = "2023-06-15 14:30:00"
    expect(instance.created_at).to be_a(Time)

    instance.created_at = Time.now
    expect(instance.created_at).to be_a(Time)

    instance.created_at = Time.now.to_i
    expect(instance.created_at).to be_a(Time)
  end

  it "serializes to integer" do
    time_value = Time.now
    serialized = field_type.serialize(time_value)
    expect(serialized).to be_a(Integer)
    expect(serialized).to eq(time_value.to_i)
  end

  it "deserializes from integer" do
    timestamp = Time.now.to_i
    deserialized = field_type.deserialize(timestamp)
    expect(deserialized).to be_a(Time)
    expect(deserialized.to_i).to eq(timestamp)
  end
end
```

## Best Practices

### 1. Choose Appropriate Field Types

```ruby
# Use built-in field types when possible
class User < Familia::Horreum
  field :name                    # Simple string field
  field :metadata, category: :json  # For complex data
  transient_field :temp_token    # For runtime-only data
  encrypted_field :api_key       # For sensitive data
end

# Create custom types for specialized behavior
class GeoLocation < Familia::Horreum
  coordinate_field :latitude     # Custom validation and formatting
  coordinate_field :longitude
end
```

### 2. Handle Method Conflicts Gracefully

```ruby
class SafeFieldDefinition < Familia::Horreum
  # Check for conflicts before defining fields
  def self.safe_field(name, **options)
    if method_defined?(name) || method_defined?(:"#{name}=")
      Rails.logger.warn "Method conflict for field #{name}, using alternative name"
      options[:as] = :"#{name}_value"
    end

    field(name, **options)
  end
end
```

### 3. Optimize for Common Use Cases

```ruby
# Provide convenience methods for common patterns
class BaseModel < Familia::Horreum
  def self.timestamps
    timestamp_field :created_at, as: :created_at
    timestamp_field :updated_at, as: :updated_at
  end

  def self.soft_delete
    boolean_field :deleted, as: :deleted
    timestamp_field :deleted_at, as: :deleted_at
  end
end
```

The Field System provides a powerful foundation for defining flexible, extensible object attributes with customizable behavior, validation, and serialization capabilities.
