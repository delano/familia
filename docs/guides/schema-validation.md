# Schema Validation

Familia supports optional JSON Schema validation for model data. Schemas are defined in external JSON files and can be shared with frontend validation, API documentation generators, and other tools.

## Overview

- **External schemas**: Define schemas as JSON files, not Ruby code
- **Shared validation**: Same schema validates Ruby models, REST APIs, frontend forms
- **Opt-in per model**: Enable with `feature :schema_validation`
- **Migration support**: Validate data before/after transforms

## Setup

### 1. Install json_schemer

Add to your Gemfile:

```ruby
gem 'json_schemer', '~> 2.0'
```

### 2. Create Schema Files

Create JSON Schema files (draft 2020-12 recommended):

```
your_app/
  schemas/
    customer.json
    session.json
    user.json
```

### 3. Configure Familia

```ruby
# config/initializers/familia.rb (Rails)
# or at application boot

Familia.configure do |config|
  # Option 1: Convention-based (recommended)
  # Files named {class_name.underscore}.json
  config.schema_path = 'schemas'

  # Option 2: Explicit mapping
  config.schemas = {
    'Customer' => 'schemas/customer.json',
    'UserSession' => 'schemas/user_session.json'
  }

  # Option 3: Disable validation
  config.schema_validator = :none
end
```

### 4. Enable on Models

```ruby
class Customer < Familia::Horreum
  feature :schema_validation

  identifier_field :custid
  field :custid
  field :email
  field :name
  field :status
end
```

## Usage

### Model Validation

```ruby
customer = Customer.new(custid: 'c1', email: 'test@example.com', name: 'Test')

# Check validity
customer.valid_against_schema?      # => true

# Get validation errors
customer.schema_validation_errors   # => []

# Validate or raise exception
customer.validate_against_schema!   # => true (or raises SchemaValidationError)
```

### Invalid Data Example

```ruby
customer = Customer.new(custid: 'c2', email: 'not-an-email')

customer.valid_against_schema?      # => false
customer.schema_validation_errors
# => [{"type"=>"format", "data_pointer"=>"/email", ...}]

customer.validate_against_schema!
# raises Familia::SchemaValidationError
```

### Migration Validation

Validate data during migrations to catch corruption:

```ruby
class NormalizeEmails < Familia::Migration::Model
  self.migration_id = '20260131_normalize_emails'

  # Enable validation hooks
  def validate_before_transform?
    true
  end

  def validate_after_transform?
    true
  end

  def process_record(customer, key)
    customer.email = customer.email.downcase
    for_realsies_this_time? { customer.save }
  end
end
```

Or validate manually:

```ruby
class DataCleanup < Familia::Migration::Base
  def migrate
    # Validate before changes
    validate_schema!(obj, context: 'before cleanup')

    # Make changes
    obj.status = 'active'

    # Validate after changes
    validate_schema!(obj, context: 'after cleanup')

    obj.save
  end
end
```

## Schema File Naming

**Convention-based** (when using `schema_path`):

| Class Name | Schema File |
|------------|-------------|
| `Customer` | `customer.json` |
| `UserSession` | `user_session.json` |
| `APIToken` | `api_token.json` |

**Explicit mapping** overrides convention:

```ruby
config.schemas = {
  'Customer' => 'schemas/v2/customer.json',
  'LegacyUser' => 'schemas/legacy/user.json'
}
```

## Graceful Degradation

- **No schema file**: Validation returns `true` (no-op)
- **No json_schemer gem**: Warning logged, validation disabled
- **Invalid JSON**: Warning logged, schema skipped

## API Reference

### Class Methods (on models with feature)

| Method | Returns | Description |
|--------|---------|-------------|
| `schema` | `Hash` or `nil` | The parsed JSON schema |
| `schema_defined?` | `Boolean` | Whether a schema exists |

### Instance Methods (on models with feature)

| Method | Returns | Description |
|--------|---------|-------------|
| `schema` | `Hash` or `nil` | The schema for this class |
| `valid_against_schema?` | `Boolean` | True if valid or no schema |
| `schema_validation_errors` | `Array` | List of error hashes |
| `validate_against_schema!` | `true` | Returns true or raises |

### Migration Methods

| Method | Description |
|--------|-------------|
| `validate_schema(obj, context:)` | Returns `{valid:, errors:}` |
| `validate_schema!(obj, context:)` | Raises on failure |
| `schema_validation_enabled?` | Check if enabled |
| `skip_schema_validation!` | Disable for this migration |

## See Also

- [JSON Schema Specification](https://json-schema.org/)
- [json_schemer gem](https://github.com/davishmcclurg/json_schemer)
- Example schemas in `examples/schemas/`
