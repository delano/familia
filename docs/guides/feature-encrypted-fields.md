# Encrypted Fields Overview

## Quick Start

Add encrypted field support to any Familia model in one line:

```ruby
class User < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :diary_entry
end
```

## What It Does

- **Automatic Encryption**: Fields are encrypted before storing in Redis/Valkey
- **Transparent Decryption**: Access encrypted fields like normal attributes
- **Modular Providers**: Pluggable encryption algorithms (XChaCha20-Poly1305, AES-GCM)
- **Secure by Default**: Uses authenticated encryption with automatic algorithm selection
- **Zero Boilerplate**: No manual encrypt/decrypt calls needed

## When to Use

Use encrypted fields for:
- Personal Identifiable Information (PII)
- API keys and secrets
- Medical records
- Financial data
- Any sensitive user data

## Basic Example

```ruby
class Customer < Familia::Horreum
  feature :encrypted_fields

  field :email                    # Regular field
  encrypted_field :secret_recipe  # Encrypted field
  encrypted_field :diary_entry    # Another encrypted field
end

# Usage is identical to regular fields
customer = Customer.new(
  email: 'user@example.com',
  secret_recipe: 'Add extra vanilla',
  diary_entry: 'Today I learned Valkey/Redis is fast'
)

customer.save
customer.secret_recipe  # => "Add extra vanilla" (decrypted automatically)
```

## Configuration

Set your encryption key in environment:

```bash
export FAMILIA_ENCRYPTION_KEY=$(openssl rand -base64 32)
```

Configure in your app:

```ruby
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY']
  }
  config.current_key_version = :v1

  # Optional: customize personalization for key derivation
  config.encryption_personalization = 'MyApp-2024'
end
```

## Advanced Features

### Per-Field Algorithm Selection

Choose specific encryption algorithms for different fields:

```ruby
class SecretVault < Familia::Horreum
  feature :encrypted_fields

  # Use default best-available algorithm
  encrypted_field :user_secret

  # Additional authenticated data for tamper detection
  encrypted_field :ultra_secure_data, aad_fields: [:vault_id, :owner]
end
```

### Provider Priority System

Familia automatically selects the best available encryption provider:

1. **XChaCha20-Poly1305** (Priority: 100) - Requires `rbnacl` gem
2. **AES-256-GCM** (Priority: 50) - Uses OpenSSL, always available

```ruby
# Check current encryption status
puts Familia::Encryption.status
# => { default_algorithm: "xchacha20poly1305",
#      available_algorithms: ["xchacha20poly1305", "aes-256-gcm"],
#      using_hardware: false,
#      key_versions: [:v1, :v2],
#      current_version: :v2 }
```

## Performance Optimization

### Request-Level Key Caching

For applications with many encryption operations in a single request:

```ruby
# Enable caching for the duration of a request
Familia::Encryption.with_request_cache do
  # Multiple encryptions reuse derived keys
  vault.secret_key = "value1"
  vault.api_token = "value2"
  vault.save  # Only derives keys once per field
end

# Clear cache manually if needed
Familia::Encryption.clear_request_cache!
```

### Benchmarking

Test encryption performance on your hardware:

```ruby
# Benchmark available providers
results = Familia::Encryption.benchmark(iterations: 1000)
# => {
#   "xchacha20poly1305" => { time: 0.45, ops_per_sec: 4444, priority: 100 },
#   "aes-256-gcm" => { time: 0.67, ops_per_sec: 2985, priority: 50 }
# }
```

## Configuration Validation

Validate your encryption setup before production:

```ruby
# Validate all encryption configuration
begin
  Familia::Encryption.validate_configuration!
  puts "✓ Encryption configuration valid"
rescue Familia::EncryptionError => e
  puts "✗ Configuration error: #{e.message}"
end
```

## Monitoring and Debugging

### Field Status Monitoring

```ruby
vault = Vault.new(secret_key: "test")
vault.save

# Check encryption status of all fields
status = vault.encrypted_fields_status
# => {
#   secret_key: { encrypted: true, cleared: false },
#   api_token: { encrypted: false, value: nil }
# }

# Check if any fields have encrypted data
vault.encrypted_data?  # => true

# Clear sensitive data from memory
vault.clear_encrypted_fields!
vault.encrypted_fields_cleared?  # => true
```

### Key Rotation

Re-encrypt fields after key rotation:

```ruby
# After updating encryption keys in configuration
vault.re_encrypt_fields!  # Uses current key version
vault.save

# Verify all fields use new key version
vault.encrypted_fields_status
```
