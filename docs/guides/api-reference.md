# API Reference

> [!NOTE]
> This document is deprecated. For comprehensive encryption API documentation, see [`docs/reference/api-technical.md`](../reference/api-technical.md) which contains complete implementation details and examples.

## Class Methods

### encrypted_field

Defines an encrypted field on a Familia::Horreum class.

```ruby
encrypted_field(name, aad_fields: [], **options)
```

**Parameters:**
- `name` (Symbol) - Field name
- `aad_fields` (Array<Symbol>) - Additional fields to include in authentication
- `**options` (Hash) - Standard field options

**Example:**
```ruby
class User < Familia::Horreum
  feature :encrypted_fields

  encrypted_field :favorite_snack
  encrypted_field :api_key
  encrypted_field :notes, aad_fields: [:user_id, :email]  # With tamper protection
end
```

### encrypted_fields

Returns list of encrypted field names.

```ruby
User.encrypted_fields  # => [:favorite_snack, :api_key]
```

## Instance Methods

### Field Accessors

Encrypted fields provide standard accessors that return ConcealedString objects:

```ruby
user.favorite_snack           # Returns ConcealedString (safe for logging)
user.favorite_snack.reveal   # Get actual decrypted value
user.favorite_snack = value   # Set and encrypt value
user.favorite_snack!          # Fast write (still encrypted)
```

**ConcealedString Methods:**
```ruby
concealed = user.favorite_snack
concealed.to_s                # => "[CONCEALED]" (safe for logging)
concealed.reveal              # => "actual value"
concealed.clear!              # Clear from memory
concealed.cleared?            # Check if cleared
```

## Familia::Encryption Module

### with_request_cache

Enables key derivation caching for performance optimization:

```ruby
Familia::Encryption.with_request_cache do
  # Multiple encryption operations reuse derived keys
  user.secret_one = "value1"
  user.secret_two = "value2"
  user.save
end
```

### clear_request_cache!

Manually clears the request-level key cache:

```ruby
Familia::Encryption.clear_request_cache!
```

### encrypt / decrypt

Low-level encryption methods (typically used internally):

```ruby
# Encrypt with context for key derivation
encrypted = Familia::Encryption.encrypt(plaintext,
  context: "User:favorite_snack:user123",
  additional_data: nil
)

# Decrypt (auto-detects algorithm from JSON)
decrypted = Familia::Encryption.decrypt(encrypted_json,
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

  # Multi-version configuration for key rotation
  config.encryption_keys = {
    v1_2024: ENV['OLD_KEY'],
    v2_2025: ENV['NEW_KEY']
  }
  config.current_key_version = :v2_2025

  # Optional personalization (XChaCha20-Poly1305 only)
  config.encryption_personalization = 'MyApp-2024'
end

# Always validate configuration
Familia::Encryption.validate_configuration!
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

### ConcealedString

String-like object that conceals sensitive data in output and provides memory safety.

```ruby
class ConcealedString
  def reveal
    # Returns actual decrypted string value
  end

  def to_s
    '[CONCEALED]'
  end

  def inspect
    '[CONCEALED]'
  end

  def clear!
    # Best-effort memory wiping
  end

  def cleared?
    # Returns true if cleared from memory
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

## Instance Methods

### encrypted_data?

Check if any encrypted fields have values:

```ruby
user.encrypted_data?  # => true if any encrypted fields have values
```

### clear_encrypted_fields!

Clear all encrypted field values from memory:

```ruby
user.clear_encrypted_fields!  # Clear all ConcealedString values
```

### encrypted_fields_cleared?

Check if all encrypted fields have been cleared:

```ruby
user.encrypted_fields_cleared?  # => true if all cleared
```

### re_encrypt_fields!

Re-encrypt all encrypted fields with current key version:

```ruby
user.re_encrypt_fields!  # Uses current_key_version
user.save
```

### encrypted_fields_status

Get encryption status for debugging:

```ruby
user.encrypted_fields_status
# => {
#   ssn: { encrypted: true, cleared: false },
#   credit_card: { encrypted: true, cleared: true }
# }
```

---

> [!IMPORTANT]
> For complete implementation details, configuration examples, and advanced usage patterns, see the comprehensive documentation in [`docs/reference/api-technical.md`](../reference/api-technical.md).
