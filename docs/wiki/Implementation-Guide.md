# Implementation Guide

## Architecture Overview

The encrypted fields feature extends Familia's existing field system with transformation hooks:

```
User Input → Field Setter → Serialize Transform → Encryption → Redis
Redis → Decryption → Deserialize Transform → Field Getter → User Output
```

## Core Components

### 1. Transform Hooks

Fields now support transform callbacks:

```ruby
FieldDefinition = Data.define(
  :field_name,
  :method_name,
  :serialize_transform,    # Called before storage
  :deserialize_transform   # Called after retrieval
)
```

### 2. Encryption Module

Handles the cryptographic operations:

```ruby
module Familia::Encryption
  # Encrypts with field-specific derived key
  def self.encrypt(plaintext, context:, additional_data: nil)

  # Decrypts and verifies authenticity
  def self.decrypt(ciphertext, context:, additional_data: nil)
end
```

### 3. Key Derivation

Each field gets a unique encryption key:

```
Master Key + Field Context → HKDF/BLAKE2b → Field-Specific Key
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
# Generate a secure key
$ familia encryption:generate_key --bits 256
# => base64_encoded_key_here

# Add to environment
$ echo "FAMILIA_ENCRYPTION_KEY_V1=base64_encoded_key_here" >> .env
```

## Advanced Usage

### Custom Field Names

```ruby
encrypted_field :ssn, as: :social_security_number
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
  { email: 'user1@example.com', ssn: '111-11-1111' },
  { email: 'user2@example.com', ssn: '222-22-2222' }
])
```

## Performance Optimization

### Request-Scoped Key Caching

```ruby
# Automatically enabled in web frameworks
# Manual control for other contexts:
Familia::Encryption.with_key_cache do
  # All operations here share derived keys
  Customer.find_each { |c| c.process }
end
```

### Memory Management

With libsodium installed:
- Keys are automatically wiped from memory
- Plaintext values cleared after use

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
  user = User.create(ssn: "123-45-6789")

  # Verify encryption in Redis
  raw_value = redis.hget(user.rediskey, "ssn")
  expect(raw_value).not_to include("123-45-6789")
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
- [Migration Guide](Migration-Guide) - Upgrade existing fields
