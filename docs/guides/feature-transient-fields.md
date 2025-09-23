# Transient Fields Guide

## Overview

Transient fields provide secure handling of sensitive runtime data that should never be persisted to Valkey/Redis. Unlike encrypted fields, transient fields exist only in memory and are automatically wrapped in `RedactedString` for security.

## When to Use Transient Fields

Use transient fields for:
- API keys and tokens that change frequently
- Temporary passwords or passphrases
- Session-specific secrets
- Any sensitive data that should never touch persistent storage
- Debug or development secrets that need secure handling

## Basic Usage

### Define Transient Fields

```ruby
class ApiClient < Familia::Horreum
  feature :transient_fields

  field :endpoint          # Regular persistent field
  transient_field :token   # Transient field (not persisted)
  transient_field :secret, as: :api_secret  # Custom accessor name
end
```

### Working with Transient Fields

```ruby
client = ApiClient.new(
  endpoint: 'https://api.example.com',
  token: ENV['API_TOKEN'],
  secret: ENV['API_SECRET']
)

# Regular field persists
client.save
client.endpoint  # => "https://api.example.com"

# Transient fields are RedactedString instances
puts client.token  # => "[REDACTED]"

# Access the actual value safely
client.token.expose do |token|
  response = HTTP.post(client.endpoint,
    headers: { 'Authorization' => "Bearer #{token}" }
  )
  # Token value is only available within this block
end

# Explicit cleanup when done
client.token.clear!
```

## RedactedString Security

### Automatic Wrapping

All transient field values are automatically wrapped in `RedactedString`:

```ruby
client = ApiClient.new(token: 'secret123')
client.token.class  # => RedactedString
```

### Safe Access Pattern

```ruby
# ✅ Recommended: Use .expose block
client.token.expose do |token|
  # Use token directly without creating copies
  HTTP.auth("Bearer #{token}")  # Safe
end

# ✅ Direct access (use carefully)
raw_token = client.token.value
# Remember to clear original source if needed

# ❌ Avoid: These create uncontrolled copies
token_copy = client.token.value.dup      # Creates copy in memory
interpolated = "Bearer #{client.token}"  # Creates copy via to_s
```

### Memory Management

```ruby
# Clear individual fields
client.token.clear!

# Check if cleared
client.token.cleared?  # => true

# Accessing cleared values raises error
client.token.value  # => SecurityError: Value already cleared
```

## Advanced Features

### Custom Accessor Names

```ruby
class Service < Familia::Horreum
  transient_field :api_key, as: :secret_key
end

service = Service.new(api_key: 'secret123')
service.secret_key.expose { |key| use_api_key(key) }
```

### Integration with Encrypted Fields

```ruby
class SecureService < Familia::Horreum
  feature :transient_fields

  encrypted_field :long_term_secret    # Persisted, encrypted
  transient_field :session_token       # Runtime only, not persisted
  field :public_endpoint               # Normal field
end

service = SecureService.new(
  long_term_secret: 'stored encrypted in Redis',
  session_token: 'temporary runtime secret',
  public_endpoint: 'https://api.example.com'
)

service.save
# Only long_term_secret and public_endpoint are saved to Redis
# session_token exists only in memory
```

## RedactedString API Reference

### Core Methods

```ruby
# Create (usually automatic via transient_field)
secret = RedactedString.new('sensitive_value')

# Safe access
secret.expose { |value| use_value(value) }

# Direct access (use with caution)
value = secret.value

# Cleanup
secret.clear!

# Status
secret.cleared?  # => true/false
```

### Security Methods

```ruby
# Logging/debugging protection
puts secret.to_s     # => "[REDACTED]"
puts secret.inspect  # => "[REDACTED]"

# Equality (object identity only)
secret1 == secret2   # => false (unless same object)

# Hash (constant for all instances)
secret.hash  # => Same for all RedactedString instances
```

## Security Considerations

### Ruby Memory Limitations

**⚠️ Important**: Ruby provides no memory safety guarantees:

- **No secure wiping**: `.clear!` is best-effort only
- **GC copying**: Garbage collector may duplicate secrets
- **String operations**: Every manipulation creates copies
- **Memory persistence**: Secrets may remain in memory indefinitely

### Best Practices

```ruby
# ✅ Wrap immediately after input
password = RedactedString.new(params[:password])
params[:password] = nil  # Clear original reference

# ✅ Use .expose for short operations
token.expose { |t| api_call(t) }

# ✅ Clear explicitly when done
token.clear!

# ✅ Avoid string operations that create copies
token.expose { |t| "Bearer #{t}" }  # Creates copy
# Better: Pass token directly to methods that need it

# ❌ Don't pass RedactedString to logging
logger.info "Token: #{token}"  # Still logs "[REDACTED]" but safer to avoid

# ❌ Don't store in instance variables outside field system
@raw_token = token.value  # Creates uncontrolled copy
```

### Production Recommendations

For highly sensitive applications, consider:
- External secrets management (HashiCorp Vault, AWS Secrets Manager)
- Hardware Security Modules (HSMs)
- Languages with secure memory handling
- Encrypted swap and memory protection at OS level

## Integration Examples

### Rails Controller

```ruby
class ApiController < ApplicationController
  def authenticate
    service = ApiService.new(
      endpoint: params[:endpoint],
      token: params[:token]  # Auto-wrapped in RedactedString
    )

    result = service.token.expose do |token|
      # Token only accessible within this block
      ExternalAPI.authenticate(token)
    end

    # Clear token when request is done
    service.token.clear!

    render json: { status: result }
  end
end
```

### Background Job

```ruby
class ApiSyncJob
  def perform(user_id, token)
    user = User.find(user_id)

    # Wrap external token securely
    secure_token = RedactedString.new(token)
    token.clear if token.respond_to?(:clear)  # Clear original

    client = ApiClient.new(token: secure_token)

    begin
      sync_data(client)
    ensure
      client.token.clear!  # Always cleanup
    end
  end

  private

  def sync_data(client)
    client.token.expose do |token|
      # Use token for API calls
      fetch_and_process_data(token)
    end
  end
end
```

## Comparison with Encrypted Fields

| Feature | Encrypted Fields | Transient Fields |
|---------|------------------|------------------|
| **Persistence** | Saved to Valkey/Redis | Memory only |
| **Encryption** | AES/XChaCha20 | None (not stored) |
| **Use Case** | Long-term secrets | Runtime secrets |
| **Access** | Automatic decrypt | RedactedString wrapper |
| **Performance** | Crypto overhead | No crypto operations |
| **Lifecycle** | Survives restarts | Cleared on restart |

Choose encrypted fields for data that must persist across sessions. Choose transient fields for sensitive runtime data that should never be stored.
