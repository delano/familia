# Familia Encrypted Fields Documentation

Welcome to the Familia encrypted fields feature documentation. This Wiki provides comprehensive guides for implementing field-level encryption in your Familia-based applications.

## 📚 Documentation Structure

### Essential Reading (Start Here)

1. **[Encrypted Fields Overview](Encrypted-Fields-Overview)** - Quick introduction and basic usage
   - What it does and when to use it
   - Quick start example
   - Basic configuration

2. **[Implementation Guide](Implementation-Guide)** - Step-by-step setup
   - Architecture overview
   - Configuration details
   - Advanced usage patterns

3. **[API Reference](API-Reference)** - Complete method documentation
   - All classes and methods
   - Configuration options
   - CLI commands

### Deep Dives

4. **[Security Model](Security-Model)** - Cryptographic design and threat model
   - Encryption algorithms
   - Protected vs unprotected scenarios
   - Compliance considerations

### Operations (As Needed)

5. **[Migration Guide](Migration-Guide)** - Upgrading existing fields _(coming soon)_
6. **[Key Management](Key-Management)** - Rotation and best practices _(coming soon)_

## 🚀 Quick Start

```ruby
# 1. Add encrypted field to your model
class User < Familia::Horreum
  encrypted_field :ssn
end

# 2. Configure encryption key
Familia.configure do |config|
  config.encryption_keys = { v1: ENV['FAMILIA_ENCRYPTION_KEY'] }
  config.current_key_version = :v1
end

# 3. Use like any other field
user = User.new(ssn: "123-45-6789")
user.save
user.ssn  # => "123-45-6789" (automatically decrypted)
```

## 🎯 Design Philosophy

This feature follows the Pareto Principle - providing 80% of the value with 20% of the complexity:

- **Secure by Default** - Strong encryption without configuration complexity
- **Zero Boilerplate** - Single line to add encryption
- **Transparent Usage** - Encrypted fields work like regular fields
- **Progressive Enhancement** - Use better crypto when available (libsodium)

## 🔒 Security First

All design decisions prioritize security while maintaining simplicity:

- Authenticated encryption (prevents tampering)
- Unique keys per field (limits breach impact)
- Random nonces (prevents pattern analysis)
- Memory safety with libsodium (when available)

## 📖 Related Resources

- [Familia README](https://github.com/delano/familia) - Main project documentation
- [Issue #57](https://github.com/delano/familia/issues/57) - Original feature proposal
- [Issue #58](https://github.com/delano/familia/issues/58) - Wiki documentation tracking

## 💡 Getting Help

- Check the [Implementation Guide](Implementation-Guide) for common issues
- Review the [API Reference](API-Reference) for method details
- Open an issue for bugs or feature requests

---

*This documentation focuses on practical implementation over theoretical completeness - providing what you need to ship secure features without unnecessary complexity.*
