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
│ - derive_key()  │    │ - available()    │    │                 │
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

  # Get available algorithm names
  def self.available_algorithms
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
  NONCE_SIZE = 12  # or 24 for XChaCha20
  AUTH_TAG_SIZE = 16

  def self.available?        # Check if dependencies are met
  def self.priority          # Higher = preferred (XChaCha20: 100, AES: 50)

  def encrypt(plaintext, key, additional_data)
  def decrypt(ciphertext, key, nonce, auth_tag, additional_data)
  def derive_key(master_key, context, personal: nil)
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
  # Add the feature
  feature :encrypted_fields

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
  config.encryption_personalization = 'MyApp-2024'  # Optional
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

### Additional Authenticated Data (AAD)

```ruby
class SecureDocument < Familia::Horreum
  feature :encrypted_fields

  field :doc_id, :owner_id, :classification
  encrypted_field :content, aad_fields: [:doc_id, :owner_id, :classification]
end

# The content can only be decrypted if doc_id, owner_id, and classification
# values match those used during encryption
```

### Request-Level Caching

```ruby
# For performance optimization
Familia::Encryption.with_request_cache do
  vault.secret_key = "value1"
  vault.api_token = "value2"
  vault.save  # Reuses derived keys within this block
end

# Cache is automatically cleared when block exits
# Or manually: Familia::Encryption.clear_request_cache!
```

### ConcealedString Objects

Encrypted fields return ConcealedString objects to prevent accidental exposure:

```ruby
secret = vault.secret_key
secret.class               # => ConcealedString
puts secret                # => "[CONCEALED]" (automatic redaction)
secret.inspect             # => "[CONCEALED]" (automatic redaction)

# Safe access pattern - requires explicit reveal
secret.reveal do |raw_value|
  # Use raw_value carefully - avoid creating copies
  HTTP.post('/api', headers: { 'X-Token' => raw_value })
end

# Check if cleared from memory
secret.cleared?            # Returns true if wiped

# Explicit cleanup
secret.clear!              # Best-effort memory wiping
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
# - 256-bit keys, 96-bit nonces (12 bytes)
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

### Monitoring Key Derivation

```ruby
# Monitor key derivations (should increment with each operation)
puts Familia::Encryption.derivation_count.value
# => 42

# Reset counter for testing
Familia::Encryption.reset_derivation_count!
```

### Encryption Status

```ruby
# Get current encryption setup info
status = Familia::Encryption.status
# => {
#   default_algorithm: "xchacha20poly1305",
#   available_algorithms: ["xchacha20poly1305", "aes-256-gcm"],
#   preferred_available: "Familia::Encryption::Providers::XChaCha20Poly1305Provider",
#   using_hardware: false,
#   key_versions: [:v1, :v2],
#   current_version: :v2
# }
```

## Field-Level Features

### Instance Methods

```ruby
vault = Vault.new(secret_key: 'secret', api_token: 'token123')

# Check if any encrypted fields have values
vault.encrypted_data?           # => true

# Clear all encrypted field values from memory
vault.clear_encrypted_fields!

# Check if all encrypted fields have been cleared
vault.encrypted_fields_cleared? # => true

# Re-encrypt all fields with current settings (for key rotation)
vault.re_encrypt_fields!
vault.save

# Get encryption status for all encrypted fields
status = vault.encrypted_fields_status
# => {
#   secret_key: { encrypted: true, algorithm: "xchacha20poly1305", cleared: false },
#   api_token: { encrypted: true, cleared: true }
# }
```

### Class Methods

```ruby
class Vault < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :secret_key
  encrypted_field :api_token
end

# Get list of encrypted field names
Vault.encrypted_fields          # => [:secret_key, :api_token]

# Check if a field is encrypted
Vault.encrypted_field?(:secret_key)  # => true
Vault.encrypted_field?(:name)        # => false
```

## Key Rotation

The feature supports key versioning for seamless key rotation:

```ruby
# Step 1: Add new key version while keeping old keys
Familia.configure do |config|
  config.encryption_keys = {
    v1: old_key,
    v2: new_key
  }
  config.current_key_version = :v2
end

# Step 2: Objects decrypt with any valid key, encrypt with current key
vault.secret_key = "new-secret"  # Encrypted with v2 key
vault.save

# Step 3: Re-encrypt existing records
vault.re_encrypt_fields!  # Uses current key version
vault.save

# Step 4: After all data is re-encrypted, remove old key
```

## Error Handling

The feature provides specific error types for different failure modes:

```ruby
# Invalid ciphertext or tampering
begin
  vault.secret_key.reveal { |s| s }
rescue Familia::EncryptionError => e
  # "Decryption failed - invalid key or corrupted data"
end

# Missing encryption configuration
Familia.config.encryption_keys = {}
begin
  vault.secret_key.reveal { |s| s }
rescue Familia::EncryptionError => e
  # "No encryption keys configured"
end

# Invalid key version
begin
  vault.secret_key.reveal { |s| s }
rescue Familia::EncryptionError => e
  # "No key for version: v1"
end
```

## Testing

```ruby
# Test helper setup
Familia.config.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.current_key_version = :v1

# In tests
it "encrypts sensitive fields" do
  user = User.create(api_token: "secret-token")

  # Verify encryption in Redis
  raw_value = redis.hget(user.dbkey, "api_token")
  expect(raw_value).not_to include("secret-token")

  encrypted_data = JSON.parse(raw_value)
  expect(encrypted_data).to have_key("ciphertext")
  expect(encrypted_data).to have_key("algorithm")
end

it "provides concealed string access" do
  user = User.create(api_token: "secret-token")
  concealed = user.api_token

  expect(concealed).to be_a(ConcealedString)
  expect(concealed.to_s).to eq("[CONCEALED]")

  concealed.reveal do |token|
    expect(token).to eq("secret-token")
  end
end
```

## Security Model

### Ciphertext Format

Encrypted data is stored as JSON with algorithm-specific metadata:

```json
{
  "algorithm": "xchacha20poly1305",
  "nonce": "base64_encoded_nonce",
  "ciphertext": "base64_encoded_data",
  "auth_tag": "base64_encoded_tag",
  "key_version": "v1"
}
```

### Memory Safety Limitations

⚠️ **Important**: Ruby provides NO memory safety guarantees:
- No secure memory wiping (best-effort only)
- Garbage collector may copy secrets
- String operations create uncontrolled copies
- Memory dumps may contain plaintext secrets

For highly sensitive applications, consider:
- External key management (HashiCorp Vault, AWS KMS)
- Hardware Security Modules (HSMs)
- Languages with secure memory handling
- Dedicated cryptographic appliances

### Threat Model

✅ **Protected Against:**
- Database compromise (encrypted data only)
- Field value swapping (field-specific keys)
- Cross-record attacks (record-specific keys)
- Tampering (authenticated encryption)

❌ **Not Protected Against:**
- Master key compromise (all data compromised)
- Application memory compromise (plaintext in RAM)
- Side-channel attacks (timing, power analysis)
- Insider threats with application access

## Troubleshooting

### Common Issues

1. **"No encryption key configured"**
   - Ensure `FAMILIA_ENCRYPTION_KEY` is set
   - Check `Familia.config.encryption_keys`

2. **"Decryption failed"**
   - Verify correct key version
   - Check if data was encrypted with different key
   - Ensure AAD fields haven't changed

3. **Performance degradation**
   - Enable request-level caching with `with_request_cache`
   - Consider installing RbNaCl gem for XChaCha20

4. **Provider not available**
   - Install RbNaCl for XChaCha20: `gem install rbnacl`
   - Falls back to AES-256-GCM automatically

## API Reference

### Module Methods

```ruby
# Main encryption/decryption
Familia::Encryption.encrypt(plaintext, context:, additional_data: nil)
Familia::Encryption.decrypt(encrypted_json, context:, additional_data: nil)
Familia::Encryption.encrypt_with(algorithm, plaintext, context:, additional_data: nil)

# Configuration and status
Familia::Encryption.validate_configuration!
Familia::Encryption.status
Familia::Encryption.benchmark(iterations: 1000)

# Request caching
Familia::Encryption.with_request_cache { block }
Familia::Encryption.clear_request_cache!

# Monitoring
Familia::Encryption.derivation_count
Familia::Encryption.reset_derivation_count!
```
