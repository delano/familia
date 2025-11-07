# Implementation Guide

## Architecture Overview

The encrypted fields feature uses a modular provider system with field transformation hooks:

```
User Input → Field Setter → Provider Selection → Encryption → Valkey/Redis
Valkey/Redis → Algorithm Detection → Decryption → Field Getter → User Output
```

### Provider Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Manager       │    │    Registry      │    │   Providers     │
│                 │    │                  │    │                 │
│ - encrypt()     │───→│ - get()          │───→│ XChaCha20Poly   │
│ - decrypt()     │    │ - register()     │    │ AES-GCM         │
│ - derive_key()  │    │ - priority       │    │ (Future: More)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Core Components

### 1. Registry System

The Registry manages available encryption providers and selects the best one:

```ruby
module Familia::Encryption::Registry
  # Auto-register available providers by priority
  def self.setup!

  # Get provider instance by algorithm
  def self.get(algorithm)

  # Get highest-priority available provider
  def self.default_provider
end
```

### 2. Manager Class

The Manager handles encryption/decryption operations with provider delegation:

```ruby
class Familia::Encryption::Manager
  # Use specific algorithm or auto-select best
  def initialize(algorithm: nil)

  # Encrypt with context-specific key derivation
  def encrypt(plaintext, context:, additional_data: nil)

  # Decrypt with automatic algorithm detection
  def decrypt(encrypted_json, context:, additional_data: nil)
end
```

### 3. Provider Interface

All providers implement a common interface:

```ruby
class Provider
  ALGORITHM = 'algorithm-name'

  def self.available?        # Check if dependencies are met
  def self.priority          # Higher = preferred (XChaCha20: 100, AES: 50)

  def encrypt(plaintext, key, additional_data)
  def decrypt(ciphertext, key, nonce, auth_tag, additional_data)
  def derive_key(master_key, context)
  def generate_nonce
end
```

### 4. Key Derivation

Each field gets a unique encryption key using provider-specific methods:

```
Master Key + Field Context → Provider KDF → Field-Specific Key

XChaCha20-Poly1305: BLAKE2b with personalization
AES-256-GCM:        HKDF-SHA256
```

## Implementation Steps

### Step 1: Enable Encryption

```ruby
class MyModel < Familia::Horreum
  # Add the feature (optional if globally enabled)
  feature :encryption

  # Define encrypted fields
  encrypted_field :sensitive_data
  encrypted_field :api_key
end
```

### Step 2: Configure Keys

```ruby
# config/initializers/familia.rb
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY_V1']
  }
  config.current_key_version = :v1
end

# Validate configuration at startup
Familia::Encryption.validate_configuration!
```

### Step 3: Generate Keys

```bash
# Generate a secure 256-bit key (32 bytes)
$ openssl rand -base64 32
# => base64_encoded_key_here

# Add to environment
$ echo "FAMILIA_ENCRYPTION_KEY_V1=base64_encoded_key_here" >> .env
```

### Step 4: Install Optional Dependencies

For best security and performance, install RbNaCl:

```bash
# Add to Gemfile
gem 'rbnacl', '~> 7.1', '>= 7.1.1'

# Install
$ bundle install
```

Without RbNaCl, Familia falls back to OpenSSL AES-256-GCM (still secure but lower priority).

## Advanced Usage

### Custom Field Names

```ruby
encrypted_field :favorite_snack, as: :top_secret_snack_preference
```

### Passphrase Protection

```ruby
class Vault < Familia::Horreum
  encrypted_field :secret

  def unlock(passphrase)
    # Passphrase becomes part of encryption context
    self.secret(passphrase_value: passphrase)
  end
end
```

### Batch Operations

```ruby
# Efficient bulk encryption
customers = Customer.batch_create([
  { email: 'user1@example.com', favorite_snack: 'chocolate chip cookies' },
  { email: 'user2@example.com', favorite_snack: 'leftover pizza' }
])
```

## Provider-Specific Features

### XChaCha20-Poly1305 Provider (Recommended)

```ruby
# Enable with RbNaCl gem
gem 'rbnacl', '~> 7.1'

# Benefits:
# - Extended nonce (192 bits vs 96 bits)
# - Better resistance to nonce reuse
# - BLAKE2b key derivation with personalization
# - Priority: 100 (highest)
```

### AES-256-GCM Provider (Fallback)

```ruby
# Always available with OpenSSL
# - 256-bit keys, 96-bit nonces
# - HKDF-SHA256 key derivation
# - Priority: 50
# - Good compatibility, proven security
```

## Performance Optimization

### Provider Benchmarking

```ruby
# Compare provider performance
results = Familia::Encryption.benchmark(iterations: 1000)
puts results
# => {
#   "xchacha20poly1305" => { time: 0.45, ops_per_sec: 4444, priority: 100 },
#   "aes-256-gcm"       => { time: 0.52, ops_per_sec: 3846, priority: 50 }
# }
```

### Key Derivation Monitoring

```ruby
# Monitor key derivations (should increment with each operation)
puts Familia::Encryption.derivation_count.value
# => 42

# Reset counter for testing
Familia::Encryption.reset_derivation_count!
```

### Memory Management

**⚠️ Important**: Ruby provides no memory safety guarantees. See security warnings in provider files.

- Keys are cleared from variables after use (best effort)
- No protection against memory dumps or GC copying
- Plaintext exists in Ruby strings during processing

## Testing

```ruby
# Test helper
RSpec.configure do |config|
  config.include Familia::EncryptionTestHelpers

  config.around(:each, :encryption) do |example|
    with_test_encryption_keys { example.run }
  end
end

# In tests
it "encrypts sensitive fields", :encryption do
  user = User.create(favorite_snack: "leftover pizza")

  # Verify encryption in Redis
  raw_value = redis.hget(user.dbkey, "favorite_snack")
  expect(raw_value).not_to include("leftover pizza")
  expect(JSON.parse(raw_value)).to have_key("ciphertext")
end
```

## Troubleshooting

### Common Issues

1. **"No encryption key configured"**
   - Ensure `FAMILIA_ENCRYPTION_KEY` is set
   - Check `Familia.config.encryption_keys`

2. **"Decryption failed"**
   - Verify correct key version
   - Check if data was encrypted with different key

3. **Performance degradation**
   - Enable key caching
   - Consider installing libsodium gem

## Next Steps

- [Security Model](Security-Model) - Understand the cryptographic design
- [Key Management](Key-Management) - Rotation and best practices
- [Migrating Guide](Migrating-Guide) - Upgrade existing fields
