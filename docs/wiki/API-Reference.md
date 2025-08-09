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
  encrypted_field :favorite_snack
  encrypted_field :api_key, as: :secret_key
end
```

### encrypted_fields

Returns list of encrypted field names.

```ruby
User.encrypted_fields  # => [:favorite_snack, :api_key]
```

## Instance Methods

### Field Accessors

Encrypted fields provide standard accessors:

```ruby
user.favorite_snack           # Get decrypted value
user.favorite_snack = value   # Set and encrypt value
user.favorite_snack!          # Fast write (still encrypted)
```

### Passphrase-Protected Access

```ruby
# For passphrase-protected fields
vault.secret_data(passphrase_value: "user_passphrase")
```

## Familia::Encryption Module

### manager

Creates a manager instance with optional algorithm selection.

```ruby
# Use best available provider
mgr = Familia::Encryption.manager

# Use specific algorithm
mgr = Familia::Encryption.manager(algorithm: 'xchacha20poly1305')
```

### encrypt

Encrypts plaintext using the default provider.

```ruby
Familia::Encryption.encrypt(plaintext,
  context: "User:favorite_snack:user123",
  additional_data: nil
)
```

### encrypt_with

Encrypts plaintext with a specific algorithm.

```ruby
Familia::Encryption.encrypt_with('aes-256-gcm', plaintext,
  context: "User:favorite_snack:user123",
  additional_data: nil
)
```

### decrypt

Decrypts ciphertext (auto-detects algorithm from JSON).

```ruby
Familia::Encryption.decrypt(encrypted_json,
  context: "User:favorite_snack:user123",
  additional_data: nil
)
```

### status

Returns current encryption configuration and available providers.

```ruby
Familia::Encryption.status
# => {
#   default_algorithm: "xchacha20poly1305",
#   available_algorithms: ["xchacha20poly1305", "aes-256-gcm"],
#   preferred_available: "Familia::Encryption::Providers::XChaCha20Poly1305Provider",
#   using_hardware: false,
#   key_versions: [:v1],
#   current_version: :v1
# }
```

### benchmark

Benchmarks available providers.

```ruby
Familia::Encryption.benchmark(iterations: 1000)
# => {
#   "xchacha20poly1305" => { time: 0.45, ops_per_sec: 4444, priority: 100 },
#   "aes-256-gcm" => { time: 0.52, ops_per_sec: 3846, priority: 50 }
# }
```

### validate_configuration!

Validates encryption configuration at startup.

```ruby
Familia::Encryption.validate_configuration!
# Raises Familia::EncryptionError if configuration invalid
```

### derivation_count / reset_derivation_count!

Monitors key derivation operations (for testing and debugging).

```ruby
# Check how many key derivations have occurred
count = Familia::Encryption.derivation_count.value
# => 42

# Reset counter
Familia::Encryption.reset_derivation_count!
```

## Familia::Encryption::Manager

Low-level manager class for direct provider control.

### initialize

```ruby
# Use default provider
manager = Familia::Encryption::Manager.new

# Use specific algorithm
manager = Familia::Encryption::Manager.new(algorithm: 'aes-256-gcm')
```

### encrypt / decrypt

Same interface as module-level methods but tied to specific provider.

## Familia::Encryption::Registry

Provider management system.

### setup!

Registers all available providers.

### get

Returns provider instance by algorithm name.

### default_provider

Returns highest-priority available provider instance.

### available_algorithms

Returns array of available algorithm names.

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
  user.decrypt_field(:favorite_snack)
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
$ familia encryption:verify [--model User] [--field favorite_snack]
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

  it "encrypts favorite snack field" do
    with_test_encryption_keys do
      user = User.create(favorite_snack: "chocolate chip cookies")

      assert_field_encrypted(user, :favorite_snack)
      assert_decryption_works(user, :favorite_snack, "chocolate chip cookies")
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
User.batch_decrypt(:favorite_snack) do |users|
  users.each { |u| process(u.favorite_snack) }
end
```
