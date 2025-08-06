# Familia Encrypted Fields Documentation

Welcome to the Familia encrypted fields feature documentation. This Wiki provides comprehensive guides for implementing field-level encryption in your Familia-based applications.

## 📚 Documentation Structure

### Essential Reading (Start Here)

1. **[Encrypted Fields Overview](Encrypted-Fields-Overview.md)** - Quick introduction and basic usage

2. **[Implementation Guide](Implementation-Guide.md)** - Configuration details and advanced usage

3. **[API Reference](API-Reference.md)** - Class and method documentation

### Deep Dives

4. **[Security Model](Security-Model.md)** - Cryptographic design and Protected vs unprotected scenarios

### Operations (As Needed)

5. **[Migration Guide](Migration-Guide.md)** - Upgrading existing fields _(coming soon)_
6. **[Key Management](Key-Management.md)** - Rotation and best practices _(coming soon)_

## 🚀 Quick Start

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


## Related Resources

- [Familia README](https://github.com/delano/familia) - Main project documentation
- [Issue #57](https://github.com/delano/familia/issues/57) - Original feature proposal
- [Issue #58](https://github.com/delano/familia/issues/58) - Wiki documentation tracking
