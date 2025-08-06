# API Reference

## Class Methods

### encrypted_field

Defines an encrypted field on a Familia::Horreum class.

```ruby
encrypted_field(name, **options)
```

**Parameters:**
- `name` (Symbol) - Field name
- `**options` (Hash) - Standard field options plus encryption-specific options

**Options:**
- `:as` - Custom accessor method name
- `:on_conflict` - Conflict resolution (always `:raise` for encrypted fields)

**Example:**
```ruby
class User < Familia::Horreum
  encrypted_field :ssn
  encrypted_field :api_key, as: :secret_key
end
```

### encrypted_fields

Returns list of encrypted field names.

```ruby
User.encrypted_fields  # => [:ssn, :api_key]
```

## Instance Methods

### Field Accessors

Encrypted fields provide standard accessors:

```ruby
user.ssn           # Get decrypted value
user.ssn = value   # Set and encrypt value
user.ssn!          # Fast write (still encrypted)
```

### Passphrase-Protected Access

```ruby
# For passphrase-protected fields
vault.secret_data(passphrase_value: "user_passphrase")
```

## Familia::Encryption Module

### encrypt

Encrypts plaintext with context-specific key.

```ruby
Familia::Encryption.encrypt(plaintext,
  context: "User:ssn:user123",
  additional_data: nil
)
```

**Parameters:**
- `plaintext` (String) - Data to encrypt
- `context` (String) - Key derivation context
- `additional_data` (String, nil) - Optional AAD for authentication

**Returns:** JSON string with encrypted data structure

### decrypt

Decrypts ciphertext with context-specific key.

```ruby
Familia::Encryption.decrypt(encrypted_json,
  context: "User:ssn:user123",
  additional_data: nil
)
```

**Parameters:**
- `encrypted_json` (String) - JSON-encoded encrypted data
- `context` (String) - Key derivation context
- `additional_data` (String, nil) - Optional AAD for verification

**Returns:** Decrypted plaintext string

### validate_configuration!

Validates encryption configuration at startup.

```ruby
Familia::Encryption.validate_configuration!
# Raises Familia::EncryptionError if configuration invalid
```

### with_key_cache

Provides request-scoped key caching.

```ruby
Familia::Encryption.with_key_cache do
  # Operations here share derived keys
  users.each { |u| u.decrypt_fields }
end
```

## Configuration

### Familia.configure

```ruby
Familia.configure do |config|
  # Single key configuration
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY']
  }
  config.current_key_version = :v1

  # Multi-version configuration
  config.encryption_keys = {
    v1_2024: ENV['OLD_KEY'],
    v2_2025: ENV['NEW_KEY']
  }
  config.current_key_version = :v2_2025

  # Key cache TTL (seconds)
  config.key_cache_ttl = 300  # Default: 5 minutes
end
```

## Data Types

### EncryptedData

Internal data structure for encrypted values.

```ruby
EncryptedData = Data.define(
  :library,      # "libsodium" or "openssl"
  :algorithm,    # "xchacha20poly1305" or "aes-256-gcm"
  :nonce,        # Base64-encoded nonce/IV
  :ciphertext,   # Base64-encoded ciphertext
  :key_version   # Key version identifier
)
```

### RedactedString

String subclass that redacts sensitive data in output.

```ruby
class RedactedString < String
  def to_s
    '[REDACTED]'
  end

  def inspect
    '[REDACTED]'
  end
end
```

## Exceptions

### Familia::EncryptionError

Raised for encryption/decryption failures.

```ruby
begin
  user.decrypt_field(:ssn)
rescue Familia::EncryptionError => e
  case e.message
  when /key version/
    # Handle key version mismatch
  when /authentication/
    # Handle tampering
  else
    # Handle other errors
  end
end
```

## CLI Commands

### Generate Key

```bash
$ familia encryption:generate_key [--bits 256]
# Outputs Base64-encoded key
```

### Verify Encryption

```bash
$ familia encryption:verify [--model User] [--field ssn]
# Verifies field encryption is working
```

### Rotate Keys

```bash
$ familia encryption:rotate [--from v1] [--to v2]
# Migrates encrypted fields to new key
```

## Testing Helpers

### EncryptionTestHelpers

```ruby
module Familia::EncryptionTestHelpers
  # Set up test encryption keys
  def with_test_encryption_keys(&block)

  # Verify field is encrypted in storage
  def assert_field_encrypted(model, field)

  # Verify decryption works
  def assert_decryption_works(model, field, expected)
end
```

### RSpec Example

```ruby
RSpec.describe User do
  include Familia::EncryptionTestHelpers

  it "encrypts SSN field" do
    with_test_encryption_keys do
      user = User.create(ssn: "123-45-6789")

      assert_field_encrypted(user, :ssn)
      assert_decryption_works(user, :ssn, "123-45-6789")
    end
  end
end
```

## Performance Considerations

### Key Derivation Caching

```ruby
# Automatic in web requests
class ApplicationController
  around_action :with_encryption_cache

  def with_encryption_cache
    Familia::Encryption.with_key_cache { yield }
  end
end
```

### Batch Operations

```ruby
# Efficient for bulk operations
User.batch_decrypt(:ssn) do |users|
  users.each { |u| process(u.ssn) }
end
```

## Version Compatibility

| Familia Version | Feature Available | Libsodium Support |
|----------------|-------------------|-------------------|
| >= 2.0.0       | ✅                | Optional          |
| >= 2.1.0       | ✅                | Recommended       |
| >= 3.0.0       | ✅                | Required          |
