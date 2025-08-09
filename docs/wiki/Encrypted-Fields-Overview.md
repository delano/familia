# Encrypted Fields Overview

## Quick Start

Add encrypted field support to any Familia model in one line:

```ruby
class User < Familia::Horreum
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
  field :email                    # Regular field
  encrypted_field :secret_recipe  # Encrypted field
  encrypted_field :diary_entry    # Another encrypted field
end

# Usage is identical to regular fields
customer = Customer.new(
  email: 'user@example.com',
  secret_recipe: 'Add extra vanilla',
  diary_entry: 'Today I learned Redis is fast'
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
  # Use default best-available algorithm
  encrypted_field :user_secret

  # Force specific algorithm (when implemented)
  # encrypted_field :ultra_secure_data, algorithm: 'xchacha20poly1305'
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
#      using_hardware: false }
```
