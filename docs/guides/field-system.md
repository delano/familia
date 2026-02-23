# Field System Guide

## Overview

Familia's Field System provides a flexible, extensible architecture for defining and managing object attributes with customizable behavior, conflict resolution, and serialization. The system uses a FieldType-based architecture that separates field definition from implementation, enabling custom field behaviors and advanced features.

## Core Architecture

### FieldType System

The Field System is built around the `FieldType` class hierarchy:

```
FieldType                        # Base class for all field types
├── TransientFieldType           # Non-persistent fields (memory only)
├── EncryptedFieldType           # Encrypted storage fields
├── ExternalIdentifierFieldType  # External ID fields
├── ObjectIdentifierFieldType    # Object ID fields
└── Custom field types           # User-defined field behaviors
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

### Method Conflict Resolution

Familia provides several strategies for handling method name conflicts:

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

## Special Field Types

### Transient Fields

Transient fields exist only in memory and are never persisted to the database. Values are automatically wrapped in `RedactedString` objects for security:

```ruby
class SecretService < Familia::Horreum
  feature :transient_fields

  field :name                    # Regular persistent field
  transient_field :api_key       # Wrapped in RedactedString
  transient_field :password      # Not persisted to database
end

service = SecretService.new
service.api_key = "sk-1234567890"
service.api_key.class           #=> RedactedString
puts service.api_key            #=> "[REDACTED]"

# Safe access pattern
service.api_key.expose do |key|
  HTTP.post(url, headers: { 'Authorization' => "Bearer #{key}" })
end
```

### Encrypted Fields

Encrypted fields provide transparent encryption/decryption with strong cryptographic protection:

```ruby
class Document < Familia::Horreum
  feature :encrypted_fields

  field :title                           # Plaintext
  encrypted_field :content               # Encrypted storage
  encrypted_field :api_key, aad_fields: [:title]  # With additional authentication
end

doc = Document.new(title: "Secret", content: "classified info")
doc.content.class               #=> ConcealedString
puts doc.content                #=> "[CONCEALED]"

# Explicit access required
doc.content.reveal do |plaintext|
  puts plaintext                # => "classified info"
end
```

## Data Type Fields

Familia provides Redis/Valkey data structure fields through the related fields system:

```ruby
class User < Familia::Horreum
  identifier_field :user_id
  field :user_id, :name, :email

  # Redis data structure fields
  list :activity_log           # Redis LIST
  set :permissions             # Redis SET
  sorted_set :scores           # Redis ZSET
  hashkey :preferences         # Redis HASH
  counter :login_count         # Redis counter
end

user = User.new(user_id: 'u123')
user.activity_log << "logged in"
user.permissions.add("read")
user.scores.add("quiz1", 95)
user.preferences["theme"] = "dark"
user.login_count.increment
```

## Collection Member Serialization

DataType collections (lists, sets, sorted sets, hash keys) and hashkey fields use different serialization strategies based on what they store.

### Fields: JSON Serialization for Type Preservation

Hashkey fields store arbitrary Ruby values — integers, booleans, hashes, nil. All values are JSON-encoded so types survive the Redis round-trip. An Integer `35` stores as `"35"` and loads back as Integer `35`, not String `"35"`.

### Collections: Raw Identifiers for Object References

When a collection's members represent references to Familia objects, those members must be stored as **raw identifier strings** — not JSON-encoded. Identifiers are lookup keys: they're matched against, compared with, and used to construct Redis keys (e.g. `customer:abc-def-123:object`). JSON-encoding an identifier produces a different byte sequence (`"\"abc-def-123\""` vs `abc-def-123`), which causes silent duplicates and broken membership checks.

The `class:` and `reference: true` options on a collection declaration tell `serialize_value` that members are object references, not arbitrary values:

```ruby
class Customer < Familia::Horreum
  # Members are object references — stored as raw identifiers
  class_sorted_set :instances, class: self, reference: true

  # Members are arbitrary values — stored as JSON
  list :activity_log
end
```

With these options set, `serialize_value` normalizes both code paths:
- Passing a Familia object extracts `.identifier` and stores it raw
- Passing a String identifier for a Familia class stores it raw (same result)
- Passing any other value JSON-encodes it for type preservation

Without `class:` metadata, a collection has no way to distinguish "this string is an identifier" from "this string is an arbitrary value" — and the two paths silently diverge.

### The `instances` Sorted Set

Every Horreum subclass automatically gets a `class_sorted_set :instances` — a class-level registry of persisted objects. Members are raw identifier strings; scores are timestamps of when each object was last saved. This is the index used to enumerate all known instances of a class, check persistence, or clean up stale entries.

Because `instances` stores object references, it is declared with `class:` and `reference: true` to ensure consistent serialization regardless of whether callers pass an object or a string identifier.

## Advanced Field Types

### Creating Custom Field Types

Custom field types allow you to define specialized behavior for your fields:

```ruby
class TimestampFieldType < Familia::FieldType
  def define_setter(klass)
    field_name = @name
    method_name = @method_name

    handle_method_conflict(klass, :"#{method_name}=") do
      klass.define_method :"#{method_name}=" do |value|
        timestamp = case value
                    when Time then value.to_i
                    when String then Time.parse(value).to_i
                    when Numeric then value.to_i
                    else nil
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
    value&.to_i
  end

  def deserialize(value, _record = nil)
    value ? Time.at(value.to_i) : nil
  end

  def category
    :timestamp
  end
end

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

event = Event.new(event_id: 'e123')
event.created_at = "2024-01-01 12:00:00 UTC"
event.created_at.class        #=> Time
event.created_at.to_s         #=> "2024-01-01 12:00:00 UTC"
```

### Enum Field Type

Create fields with restricted values and validation:

```ruby
class EnumFieldType < Familia::FieldType
  def initialize(name, values:, **options)
    super(name, **options)
    @valid_values = Array(values).map(&:to_s).freeze
  end

  def define_setter(klass)
    field_name = @name
    method_name = @method_name
    valid_values = @valid_values

    handle_method_conflict(klass, :"#{method_name}=") do
      klass.define_method :"#{method_name}=" do |value|
        unless valid_values.include?(value.to_s)
          raise ArgumentError, "Invalid #{field_name}: #{value}. Valid values: #{valid_values.join(', ')}"
        end
        instance_variable_set(:"@#{field_name}", value.to_s)
      end
    end
  end

  def install(klass)
    super
    # Add constants for enum values
    @valid_values.each do |value|
      const_name = "#{@name.to_s.upcase}_#{value.upcase}"
      klass.const_set(const_name, value) unless klass.const_defined?(const_name)
    end
  end

  def category
    :enum
  end
end

class Order < Familia::Horreum
  def self.enum_field(name, values:, **options)
    field_type = EnumFieldType.new(name, values: values, **options)
    register_field_type(field_type)
  end

  identifier_field :order_id
  field :order_id, :customer_id
  enum_field :status, values: [:pending, :processing, :shipped, :delivered]
  enum_field :priority, values: [:low, :normal, :high, :urgent]
end

order = Order.new(order_id: 'o123')
order.status = :pending              # Valid
order.status = "processing"          # Valid (string converted)
order.priority = Order::PRIORITY_HIGH  # Using generated constant

# This raises ArgumentError
order.status = :invalid              # Invalid value
```

## Field Metadata and Introspection

### Accessing Field Information

```ruby
class Product < Familia::Horreum
  feature :transient_fields

  field :name
  field :price
  field :description
  transient_field :temp_data
end

# Get all field names
Product.fields                    #=> [:name, :price, :description, :temp_data]

# Get field types
Product.field_types               #=> { name: FieldType, price: FieldType, ... }

# Get persistent vs transient fields
Product.persistent_fields         #=> [:name, :price, :description]
Product.transient_fields          #=> [:temp_data]

# Check field properties
product = Product.new
field_type = Product.field_types[:temp_data]
field_type.persistent?            #=> false
field_type.transient?             #=> true
field_type.category               #=> :transient
```

### Field Categories and Filtering

Field types can specify categories for grouping and filtering:

```ruby
class SearchableFieldType < Familia::FieldType
  def category
    :searchable
  end
end

class Product < Familia::Horreum
  def self.searchable_field(name, **options)
    field_type = SearchableFieldType.new(name, **options)
    register_field_type(field_type)
  end

  searchable_field :name
  searchable_field :description
  field :internal_id

  def self.searchable_fields
    field_types.select { |_, ft| ft.category == :searchable }.keys
  end
end

Product.searchable_fields         #=> [:name, :description]
```

## Fast Methods and Database Operations

### Fast Method Behavior

Fast methods (ending with `!`) provide immediate database persistence without requiring a separate `save` call:

```ruby
class UserProfile < Familia::Horreum
  identifier_field :user_id
  field :user_id, :name, :email, :last_login_at
end

profile = UserProfile.new(user_id: 'u123')
profile.name!("John Doe")         # Immediately persists to database
profile.email!("john@example.com") # No save() needed

# Reading with fast method returns current database value
current_name = profile.name!      # Reads from database
```

### Custom Fast Method Behavior

Override fast method behavior for specialized use cases:

```ruby
class AuditedFieldType < Familia::FieldType
  def define_fast_writer(klass)
    return unless @fast_method_name&.to_s&.end_with?('!')

    field_name = @name
    method_name = @method_name
    fast_method_name = @fast_method_name

    handle_method_conflict(klass, fast_method_name) do
      klass.define_method fast_method_name do |*args|
        val = args.first
        return hget(field_name) if val.nil?

        # Audit the change
        old_value = hget(field_name)
        timestamp = Time.now.to_i

        # Log the change
        puts "AUDIT: #{field_name} changed from #{old_value} to #{val} at #{timestamp}"

        # Update instance variable
        send(:"#{method_name}=", val) if method_name

        # Persist to database
        hset(field_name, serialize_value(val))
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
```

## Field Options and Configuration

### Available Options

```ruby
field :name,
  as: :display_name,           # Custom method name
  fast_method: :name_now!,     # Custom fast method name
  fast_method: false,          # Disable fast method
  on_conflict: :skip,          # Conflict resolution strategy
  loggable: false             # Exclude from serialization
```

### Conflict Resolution Strategies

- `:raise` - Raise error if method exists (default)
- `:skip` - Skip field definition if method exists
- `:warn` - Warn but proceed with definition
- `:overwrite` - Silently overwrite existing method

## Integration Patterns

### Rails Integration

```ruby
module FamiliaFields
  extend ActiveSupport::Concern

  class_methods do
    def string_field(*names, **options)
      names.each { |name| field(name, **options) }
    end

    def integer_field(*names, **options)
      field_type = Class.new(Familia::FieldType) do
        def serialize(value, _record = nil)
          value&.to_i
        end

        def deserialize(value, _record = nil)
          value&.to_i
        end
      end

      names.each do |name|
        register_field_type(field_type.new(name, **options))
      end
    end

    def boolean_field(*names, **options)
      field_type = Class.new(Familia::FieldType) do
        def serialize(value, _record = nil)
          !!value
        end

        def deserialize(value, _record = nil)
          case value.to_s.downcase
          when 'true', '1', 'yes', 'on' then true
          when 'false', '0', 'no', 'off' then false
          else nil
          end
        end

        def define_getter(klass)
          field_name = @name
          method_name = @method_name

          handle_method_conflict(klass, method_name) do
            klass.define_method method_name do
              value = instance_variable_get(:"@#{field_name}")
              !!value
            end
          end
        end
      end

      names.each do |name|
        register_field_type(field_type.new(name, **options))
      end
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
        validations.each do |type, constraint|
          case type
          when :presence
            raise ArgumentError, "#{field_name} cannot be blank" if constraint && value.to_s.strip.empty?
          when :length
            if constraint.is_a?(Hash)
              min = constraint[:minimum] || constraint[:min]
              max = constraint[:maximum] || constraint[:max]
              len = value.to_s.length
              raise ArgumentError, "#{field_name} too short (minimum: #{min})" if min && len < min
              raise ArgumentError, "#{field_name} too long (maximum: #{max})" if max && len > max
            end
          when :format
            raise ArgumentError, "#{field_name} format invalid" if constraint && !value.to_s.match?(constraint)
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
    format: /\A[^@\s]+@[^@\s]+\z/
  }
  validated_field :status, validations: {
    presence: true,
    format: /\A(active|inactive|pending)\z/
  }
  validated_field :name, validations: {
    length: { minimum: 2, maximum: 50 }
  }
end
```

## Performance Considerations

### Efficient Field Operations

```ruby
# Batch updates using fast methods
user.name!("John")
user.email!("john@example.com")
user.status!("active")

# Use transactions for multiple operations
redis.multi do
  user.name!("John")
  user.email!("john@example.com")
  user.status!("active")
end
```

### Memory-Efficient Field Storage

```ruby
class CompactFieldType < Familia::FieldType
  def serialize(value, _record = nil)
    case value
    when String
      # Compress long strings
      value.length > 100 ? Zlib::Deflate.deflate(value) : value
    when Hash
      # Use more compact JSON representation
      value.to_json
    when Array
      # Join simple arrays
      value.all? { |v| v.is_a?(String) } ? value.join('|') : value.to_json
    else
      value
    end
  end

  def deserialize(value, _record = nil)
    return value unless value.is_a?(String)

    # Try to decompress
    if value.start_with?("\x78\x9C") # zlib magic bytes
      Zlib::Inflate.inflate(value)
    elsif value.start_with?('{', '[')
      JSON.parse(value)
    elsif value.include?('|')
      value.split('|')
    else
      value
    end
  rescue JSON::ParserError, Zlib::Error
    value # Return original if parsing fails
  end
end
```

## Testing Field Types

### RSpec Testing

```ruby
describe TimestampFieldType do
  let(:field_type) { TimestampFieldType.new(:created_at) }
  let(:test_class) do
    Class.new do
      def self.name; 'TestClass'; end
      include Familia::Horreum
    end
  end

  before do
    field_type.install(test_class)
  end

  it "converts various time formats" do
    instance = test_class.new
    instance.created_at = "2024-01-01 12:00:00 UTC"
    expect(instance.created_at).to be_a(Time)
    expect(instance.created_at.to_s).to include("2024-01-01 12:00:00")

    instance.created_at = Time.now
    expect(instance.created_at).to be_a(Time)
  end

  it "serializes to integer" do
    time = Time.parse("2024-01-01 12:00:00 UTC")
    expect(field_type.serialize(time)).to eq(time.to_i)
  end

  it "deserializes from integer" do
    timestamp = Time.parse("2024-01-01 12:00:00 UTC").to_i
    result = field_type.deserialize(timestamp)
    expect(result).to be_a(Time)
    expect(result.to_i).to eq(timestamp)
  end
end
```

## Best Practices

### 1. Choose Appropriate Field Types

```ruby
class User < Familia::Horreum
  feature :transient_fields
  feature :encrypted_fields

  field :name                    # Regular field for non-sensitive data
  field :metadata                # JSON data can be stored as regular field
  transient_field :temp_token    # Sensitive temporary data
  encrypted_field :api_key       # Sensitive persistent data
end

# Use specialized field types for domain-specific data
class GeoLocation < Familia::Horreum
  coordinate_field :latitude     # Custom validation for coordinates
  coordinate_field :longitude
end
```

### 2. Handle Method Conflicts Gracefully

```ruby
class SafeFieldDefinition < Familia::Horreum
  # Always use skip strategy for potentially conflicting names
  def self.safe_field(name, **options)
    field(name, on_conflict: :skip, **options)
  end
end
```

### 3. Optimize for Common Use Cases

```ruby
class BaseModel < Familia::Horreum
  def self.timestamps
    timestamp_field :created_at
    timestamp_field :updated_at
  end

  def self.soft_delete
    boolean_field :deleted
    timestamp_field :deleted_at
  end
end

class User < BaseModel
  timestamps
  soft_delete

  field :name, :email
end
```

### 4. Use Field Groups for Organization

```ruby
class User < Familia::Horreum
  field_group :identity do
    field :user_id
    field :email
    field :username
  end

  field_group :profile do
    field :first_name
    field :last_name
    field :avatar_url
  end

  field_group :preferences do
    field :theme
    field :language
    field :timezone
  end
end

# Access grouped fields
User.field_groups[:identity]     #=> [:user_id, :email, :username]
User.field_groups[:profile]      #=> [:first_name, :last_name, :avatar_url]
```

## API Reference

### FieldType Class

```ruby
# Constructor
FieldType.new(name, as: name, fast_method: :"#{name}!", on_conflict: :raise, loggable: true, **options)

# Key methods
field_type.install(klass)              # Install on class
field_type.define_getter(klass)        # Define getter method
field_type.define_setter(klass)        # Define setter method
field_type.define_fast_writer(klass)   # Define fast writer method
field_type.serialize(value, record)    # Serialize for storage
field_type.deserialize(value, record)  # Deserialize from storage
field_type.persistent?                 # Check if persisted
field_type.category                    # Get field category
field_type.generated_methods           # Get all generated method names
```

### Class Methods

```ruby
# Field definition
field(name, **options)                 # Define a field
register_field_type(field_type)        # Register custom field type

# Introspection
fields                                 # Get all field names
field_types                           # Get all field types
persistent_fields                     # Get persistent field names
transient_fields                      # Get transient field names
field_method_map                      # Get field name to method mappings
```
