# Familia Security Features Documentation

Welcome to the Familia security features documentation. This Wiki provides comprehensive guides for implementing field-level encryption and transient data handling in your Familia-based applications.

## 📚 Documentation Structure

### Essential Reading (Start Here)

1. **[Encrypted Fields Overview](Encrypted-Fields-Overview.md)** - Persistent encrypted storage with modular providers

2. **[Implementation Guide](Implementation-Guide.md)** - Configuration, providers, and advanced usage

3. **[API Reference](API-Reference.md)** - Complete class and method documentation

### Deep Dives

4. **[Security Model](Security-Model.md)** - Cryptographic design and Ruby memory limitations

5. **[Transient Fields Guide](Transient-Fields-Guide.md)** - Non-persistent secure data handling _(new!)_

### Operations (As Needed)

6. **[Migration Guide](Migration-Guide.md)** - Upgrading existing fields _(coming soon)_
7. **[Key Management](Key-Management.md)** - Rotation and best practices _(coming soon)_

## 🚀 Quick Start

### Encrypted Fields (Persistent)
```ruby
# 1. Add encrypted field to your model
class User < Familia::Horreum
  encrypted_field :secret_recipe
end

# 2. Configure encryption key
Familia.configure do |config|
  config.encryption_keys = { v1: ENV['FAMILIA_ENCRYPTION_KEY'] }
  config.current_key_version = :v1
end

# 3. Use like any other field
user = User.new(secret_recipe: "donna's cookies")
user.save
user.secret_recipe  # => "donna's cookies" (automatically decrypted)
```

### Transient Fields (Non-Persistent)
```ruby
# 1. Add transient field for sensitive runtime data
class ApiClient < Familia::Horreum
  feature :transient_fields
  transient_field :api_key
end

# 2. Use with automatic RedactedString wrapping
client = ApiClient.new(api_key: ENV['SECRET_API_KEY'])
client.api_key.expose { |key| HTTP.post('/api', headers: { 'Token' => key }) }
client.api_key.clear!  # Explicitly wipe from memory
```


## Related Resources

- [Familia README](https://github.com/delano/familia) - Main project documentation
- [Issue #57](https://github.com/delano/familia/issues/57) - Original feature proposal
- [Issue #58](https://github.com/delano/familia/issues/58) - Wiki documentation tracking
