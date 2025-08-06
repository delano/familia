# Encrypted Fields Overview

## Quick Start

Add encrypted field support to any Familia model in one line:
class User < Familia::Horreum
  encrypted_field :diary_entry
end
```

## What It Does

- **Automatic Encryption**: Fields are encrypted before storing in Redis/Valkey
- **Transparent Decryption**: Access encrypted fields like normal attributes
- **Secure by Default**: Uses authenticated encryption (AES-GCM or XChaCha20-Poly1305)
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
customer.credit_card  # => "4111-1111-1111-1111" (decrypted automatically)
```

## Configuration

Set your encryption key in environment:

```bash
export FAMILIA_ENCRYPTION_KEY=$(familia encryption:generate_key)
```

Configure in your app:

```ruby
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY']
  }
  config.current_key_version = :v1
end
```
