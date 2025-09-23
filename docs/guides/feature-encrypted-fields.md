# Encrypted Fields Guide

> **💡 Quick Reference**
>
> Add persistent encrypted storage to any Familia model:
> ```ruby
> class User < Familia::Horreum
>   feature :encrypted_fields
>   encrypted_field :sensitive_data
> end
> ```

## Overview

The Encrypted Fields feature provides transparent field-level encryption for sensitive data stored in Redis/Valkey. It combines industry-standard encryption algorithms with Ruby-friendly APIs, ensuring your sensitive data is protected at rest while maintaining the performance and simplicity you expect from Familia.

## Why Use Encrypted Fields?

**Compliance**: Meet regulatory requirements (GDPR, HIPAA, PCI-DSS) for sensitive data protection.

**Defense in Depth**: Protect against database breaches, memory dumps, and unauthorized Valkey/Redis access.

**Transparent Security**: Encryption and decryption happen automatically - no changes to your application logic.

**Performance Focused**: Optimized for Ruby's memory model with request-level caching and efficient key derivation.

**Future Proof**: Modular provider system supports algorithm upgrades and key rotation.

> **⚠️ Security Consideration**
>
> Encrypted fields protect data at rest in Redis/Valkey. Consider your threat model: encryption keys are held in Ruby memory and may be visible in memory dumps.

## Quick Start

### Basic Encrypted Storage

```ruby
class Customer < Familia::Horreum
  feature :encrypted_fields

  # Regular fields (stored as plaintext)
  field :email, :company_name, :created_at

  # Encrypted fields (automatically encrypted/decrypted)
  encrypted_field :api_key
  encrypted_field :notes
  encrypted_field :credit_card_last_four
end

# Configure encryption keys
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY']
  }
  config.current_key_version = :v1
end

# Usage is identical to regular fields
customer = Customer.new(
  email: 'contact@acme.com',
  company_name: 'Acme Corporation',
  api_key: 'sk-1234567890abcdef',
  notes: 'VIP customer - handle with care'
)

customer.save

# Access returns ConcealedString for safety
customer.api_key.class          # => ConcealedString
customer.api_key.to_s           # => "[CONCEALED]" (safe for logging)
customer.api_key.reveal         # => "sk-1234567890abcdef" (actual value)
```

### Key Generation and Setup

Generate secure encryption keys for your environment:

```bash
# Generate a new 32-byte key
export FAMILIA_ENCRYPTION_KEY=$(openssl rand -base64 32)

# For production, use a secure key management service
export FAMILIA_ENCRYPTION_KEY_V1="your-secure-key-from-vault"
export FAMILIA_ENCRYPTION_KEY_V2="new-key-for-rotation"
```

> **🔒 Key Management Best Practices**
>
> - Use different keys for each environment (development, staging, production)
> - Store keys in a secure key management service (AWS KMS, HashiCorp Vault)
> - Never commit keys to source control
> - Rotate keys regularly (recommended: every 90-180 days)

## Configuration Deep Dive

### Basic Configuration

```ruby
Familia.configure do |config|
  # Single key setup (simplest)
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY']
  }
  config.current_key_version = :v1

  # Optional: application-specific key derivation
  config.encryption_personalization = 'MyApp-Production-2024'
end

# Validate configuration before use
Familia::Encryption.validate_configuration!
```

### Multi-Key Configuration (Key Rotation)

```ruby
Familia.configure do |config|
  # Multiple keys for rotation
  config.encryption_keys = {
    v1: ENV['FAMILIA_ENCRYPTION_KEY_V1'],  # Legacy key
    v2: ENV['FAMILIA_ENCRYPTION_KEY_V2'],  # Current key
    v3: ENV['FAMILIA_ENCRYPTION_KEY_V3']   # New key for rotation
  }

  # New data encrypted with v3, old data readable with v1/v2
  config.current_key_version = :v3

  # Provider-specific configuration
  config.encryption_providers = {
    xchacha20_poly1305: {
      priority: 100,
      require_gem: 'rbnacl'
    },
    aes_gcm: {
      priority: 50,
      always_available: true
    }
  }
end
```

> **💡 Key Rotation Strategy**
>
> 1. Add new key version to configuration
> 2. Update `current_key_version` to new version
> 3. Deploy application (new writes use new key)
> 4. Re-encrypt existing data with `re_encrypt_fields!`
> 5. Remove old key version after migration complete

## Encryption Providers

Familia supports multiple encryption algorithms with automatic provider selection:

### XChaCha20-Poly1305 (Recommended)

The preferred encryption algorithm offering excellent security and performance:

```ruby
# Requires rbnacl gem
gem 'rbnacl', '~> 7.1'

# Automatic selection when available
class SecureVault < Familia::Horreum
  feature :encrypted_fields

  # Will use XChaCha20-Poly1305 if rbnacl is available
  encrypted_field :master_password
  encrypted_field :recovery_codes
end
```

**Characteristics:**
- **Algorithm**: XChaCha20-Poly1305 AEAD
- **Key Size**: 32 bytes (256 bits)
- **Nonce Size**: 24 bytes (192 bits) - collision resistant
- **Authentication**: Built-in with Poly1305 MAC
- **Performance**: Excellent on modern CPUs

> **🚀 Performance Tip**
>
> XChaCha20-Poly1305 is typically 20-30% faster than AES-GCM and provides better security margins.

### AES-256-GCM (Fallback)

Standard AES encryption using OpenSSL (always available):

```ruby
# No additional gems required
class StandardVault < Familia::Horreum
  feature :encrypted_fields

  # Explicitly specify AES-GCM
  encrypted_field :secret_data, provider: :aes_gcm
end
```

**Characteristics:**
- **Algorithm**: AES-256-GCM AEAD
- **Key Size**: 32 bytes (256 bits)
- **IV Size**: 12 bytes (96 bits)
- **Authentication**: Built-in with GCM mode
- **Availability**: Always available via OpenSSL

### Provider Selection Logic

```ruby
# Check available providers
providers = Familia::Encryption.available_providers
# => [
#   { name: :xchacha20_poly1305, priority: 100, available: true },
#   { name: :aes_gcm, priority: 50, available: true }
# ]

# Force specific provider for testing
class TestVault < Familia::Horreum
  feature :encrypted_fields

  encrypted_field :test_data, provider: :aes_gcm  # Force AES-GCM
end
```

## Advanced Field Configuration

### Additional Authenticated Data (AAD)

Protect against field tampering by including related fields in authentication:

```ruby
class SecureDocument < Familia::Horreum
  feature :encrypted_fields

  field :document_id, :owner_id, :created_at

  # Include document_id and owner_id in authentication
  encrypted_field :content, aad_fields: [:document_id, :owner_id]
  encrypted_field :metadata, aad_fields: [:document_id, :created_at]
end

# AAD fields are included in encryption but not encrypted themselves
doc = SecureDocument.new(
  document_id: 'doc123',
  owner_id: 'user456',
  content: 'Sensitive document content',
  created_at: Time.now.to_i
)

doc.save

# If someone modifies document_id or owner_id, decryption will fail
# This prevents attacks where encrypted data is moved between records
```

> **🛡️ Security Enhancement**
>
> AAD prevents encrypted fields from being moved between objects. Use it for high-security scenarios where data integrity is critical.

### Per-Field Provider Selection

```ruby
class MultiAlgorithmVault < Familia::Horreum
  feature :encrypted_fields

  # Use best available algorithm (XChaCha20-Poly1305 preferred)
  encrypted_field :general_secret

  # Force AES-GCM for compliance requirements
  encrypted_field :compliance_data, provider: :aes_gcm

  # High-security field with AAD
  encrypted_field :ultra_secure,
                  provider: :xchacha20_poly1305,
                  aad_fields: [:vault_id, :owner_id]
end
```

## ConcealedString Security

Encrypted fields return `ConcealedString` objects to prevent accidental exposure:

### Safe Handling

```ruby
class User < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :api_key
end

user = User.create(api_key: "sk-1234567890abcdef")

# Safe operations (won't expose actual value)
puts user.api_key.to_s                    # => "[CONCEALED]"
puts user.api_key.inspect                 # => "[CONCEALED]"
logger.info("User key: #{user.api_key}")  # => "User key: [CONCEALED]"

# JSON serialization safety
user_json = user.to_json
# All encrypted fields appear as "[CONCEALED]" in JSON

# Explicit access when needed
actual_key = user.api_key.reveal          # => "sk-1234567890abcdef"
```

### String Operations

```ruby
api_key = user.api_key

# Length operations work on concealed representation
api_key.length        # => 11 ("[CONCEALED]".length)
api_key.size          # => 11

# Comparison operations
api_key == "[CONCEALED]"              # => true
api_key.start_with?("[CONCEALED]")    # => true

# Reveal for actual operations
actual_key = api_key.reveal
actual_key.length     # => 17 (actual key length)
actual_key.start_with?("sk-")         # => true
```

> **⚠️ Important**
>
> Always use `.reveal` explicitly when you need the actual value. This makes it obvious in code reviews where sensitive data is being accessed.

## Performance Optimization

### Request-Level Caching

For applications that perform many encryption operations:

```ruby
class BulkDataProcessor
  def process_sensitive_batch(records)
    # Enable key caching for the entire batch
    Familia::Encryption.with_request_cache do
      records.each do |record|
        # Key derivation happens once per field type
        record.encrypted_field1 = process_data(record.raw_data1)
        record.encrypted_field2 = process_data(record.raw_data2)
        record.save
      end
    end
    # Cache automatically cleared at end of block
  end
end
```

**Performance Improvements:**
- Key derivation: 1x per field type instead of per operation
- Typical improvement: 40-60% faster for batch operations
- Memory usage: Minimal (keys cached temporarily)

### Benchmarking Your Setup

```ruby
# Test encryption performance with your data
def benchmark_encryption
  require 'benchmark'

  test_data = {
    small: "x" * 100,
    medium: "x" * 1000,
    large: "x" * 10000
  }

  Benchmark.bm(15) do |x|
    test_data.each do |size, data|
      x.report("#{size} (#{data.length}b)") do
        1000.times do
          TestModel.create(encrypted_field: data)
        end
      end
    end
  end
end

# Provider comparison
providers = Familia::Encryption.benchmark_providers(iterations: 1000)
providers.each do |name, stats|
  puts "#{name}: #{stats[:ops_per_sec]} ops/sec"
end
```

### Memory Management

```ruby
class MemoryAwareModel < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :large_data

  def process_and_clear
    # Process encrypted data
    result = expensive_operation(large_data.reveal)

    # Clear sensitive data from memory
    clear_encrypted_fields!

    result
  end

  def self.bulk_process_with_cleanup(ids)
    ids.each_slice(100) do |batch|
      objects = multiget(batch)

      objects.each(&:process_and_clear)

      # Force garbage collection periodically
      GC.start if batch.first % 1000 == 0
    end
  end
end
```

## Key Rotation and Migration

### Planned Key Rotation

```ruby
# 1. Add new key to configuration
Familia.configure do |config|
  config.encryption_keys = {
    v1: ENV['OLD_KEY'],
    v2: ENV['CURRENT_KEY'],
    v3: ENV['NEW_KEY']        # Add new key
  }
  config.current_key_version = :v3  # Switch to new key
end

# 2. Deploy application (new data uses v3)

# 3. Migrate existing data
class KeyRotationTask
  def self.rotate_all_encrypted_data
    model_classes = [User, Document, Vault, SecretData]

    model_classes.each do |model_class|
      puts "Rotating keys for #{model_class.name}..."

      model_class.all.each_slice(100) do |batch|
        batch.each do |record|
          begin
            record.re_encrypt_fields!
            record.save
          rescue => e
            puts "Failed to rotate #{record.identifier}: #{e.message}"
          end
        end

        print "."
        sleep 0.1  # Rate limiting
      end

      puts "\nCompleted #{model_class.name}"
    end
  end
end

# 4. Remove old key after migration
```

### Emergency Key Rotation

```ruby
# For compromised keys, rotate immediately
class EmergencyRotation
  def self.emergency_key_rotation
    # 1. Generate new key immediately
    new_key = SecureRandom.base64(32)

    # 2. Update configuration
    Familia.configure do |config|
      config.encryption_keys[:emergency] = new_key
      config.current_key_version = :emergency
    end

    # 3. Re-encrypt all data immediately
    KeyRotationTask.rotate_all_encrypted_data

    # 4. Notify security team
    SecurityNotifier.alert_key_rotated(reason: 'emergency')
  end
end
```

## Error Handling and Debugging

### Common Configuration Errors

```ruby
begin
  Familia::Encryption.validate_configuration!
rescue Familia::EncryptionError => e
  case e.message
  when /No encryption keys configured/
    puts "Add encryption keys to Familia.configure block"
  when /Invalid key format/
    puts "Keys must be base64-encoded 32-byte strings"
  when /Current key version not found/
    puts "current_key_version must exist in encryption_keys"
  else
    puts "Configuration error: #{e.message}"
  end
end
```

### Debugging Encryption Issues

```ruby
class DebugVault < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :debug_data

  def debug_encryption_status
    status = {
      feature_enabled: self.class.features_enabled.include?(:encrypted_fields),
      field_encrypted: self.class.encrypted_field?(:debug_data),
      data_encrypted: encrypted_data?,
      fields_cleared: encrypted_fields_cleared?,
      current_provider: Familia::Encryption.current_provider,
      available_providers: Familia::Encryption.available_providers
    }

    puts JSON.pretty_generate(status)
    status
  end
end

# Debug individual field encryption
vault = DebugVault.new(debug_data: "test")
vault.save

field_status = vault.encrypted_fields_status
puts "Field status: #{field_status}"
# => {debug_data: {encrypted: true, key_version: :v2, provider: :xchacha20_poly1305}}
```

### Performance Debugging

```ruby
# Monitor encryption performance
class EncryptionMonitor
  def self.monitor_encryption_calls
    original_encrypt = Familia::Encryption.method(:encrypt)

    call_count = 0
    total_time = 0

    Familia::Encryption.define_singleton_method(:encrypt) do |data, **opts|
      start_time = Time.now
      result = original_encrypt.call(data, **opts)
      total_time += (Time.now - start_time)
      call_count += 1

      if call_count % 100 == 0
        avg_time = (total_time / call_count * 1000).round(2)
        puts "Encryption calls: #{call_count}, avg: #{avg_time}ms"
      end

      result
    end
  end
end
```

## Testing Strategies

### Test Configuration

```ruby
# test/test_helper.rb
require 'familia'

# Use predictable test keys
test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}

Familia.configure do |config|
  config.encryption_keys = test_keys
  config.current_key_version = :v1
  config.encryption_personalization = 'TestApp-Test'
end

# Validate test configuration
Familia::Encryption.validate_configuration!
```

### Testing Encrypted Fields

```ruby
# test/models/encrypted_model_test.rb
require 'test_helper'

class EncryptedModelTest < Minitest::Test
  def setup
    @model = EncryptedModel.new(
      name: "Test Model",
      secret_data: "sensitive information"
    )
    @model.save
  end

  def test_encryption_concealment
    # Field should return ConcealedString
    assert_instance_of Familia::Features::EncryptedFields::ConcealedString, @model.secret_data

    # String representation should be concealed
    assert_equal "[CONCEALED]", @model.secret_data.to_s

    # Reveal should return actual value
    assert_equal "sensitive information", @model.secret_data.reveal
  end

  def test_json_serialization_safety
    json_data = @model.to_json
    parsed = JSON.parse(json_data)

    # Encrypted fields should be concealed in JSON
    assert_equal "[CONCEALED]", parsed['secret_data']

    # Regular fields should be normal
    assert_equal "Test Model", parsed['name']
  end

  def test_encryption_persistence
    # Reload from database
    reloaded = EncryptedModel.load(@model.identifier)

    # Should still be able to decrypt
    assert_equal "sensitive information", reloaded.secret_data.reveal
  end

  def test_key_rotation
    original_data = @model.secret_data.reveal

    # Simulate key rotation
    @model.re_encrypt_fields!
    @model.save

    # Should still decrypt to same value
    reloaded = EncryptedModel.load(@model.identifier)
    assert_equal original_data, reloaded.secret_data.reveal
  end
end
```

### Mock Encryption for Fast Tests

```ruby
# test/support/mock_encryption.rb
module MockEncryption
  def self.setup
    # Replace encryption with reversible encoding for speed
    Familia::Encryption.define_singleton_method(:encrypt) do |data, **opts|
      Base64.strict_encode64("MOCK:#{data}")
    end

    Familia::Encryption.define_singleton_method(:decrypt) do |encrypted_data, **opts|
      decoded = Base64.strict_decode64(encrypted_data)
      decoded.sub(/^MOCK:/, '')
    end
  end

  def self.teardown
    # Restore original encryption methods
    load 'familia/encryption.rb'
  end
end

# Use in fast test suite
class FastEncryptedModelTest < Minitest::Test
  def setup
    MockEncryption.setup
  end

  def teardown
    MockEncryption.teardown
  end

  # Tests run much faster with mock encryption
end
```

## Production Considerations

### Monitoring and Alerting

```ruby
# Monitor encryption health in production
class EncryptionHealthCheck
  def self.check
    results = {
      configuration_valid: false,
      providers_available: [],
      key_versions_accessible: [],
      sample_encrypt_decrypt: false
    }

    begin
      # Test configuration
      Familia::Encryption.validate_configuration!
      results[:configuration_valid] = true

      # Test providers
      results[:providers_available] = Familia::Encryption.available_providers.map { |p| p[:name] }

      # Test key access
      Familia.config.encryption_keys.each do |version, key|
        begin
          # Test key derivation
          Familia::Encryption.derive_key_for_field('test_field', version)
          results[:key_versions_accessible] << version
        rescue => e
          puts "Key version #{version} error: #{e.message}"
        end
      end

      # Test encrypt/decrypt cycle
      test_data = "health_check_#{Time.now.to_i}"
      encrypted = Familia::Encryption.encrypt(test_data)
      decrypted = Familia::Encryption.decrypt(encrypted)
      results[:sample_encrypt_decrypt] = (decrypted == test_data)

    rescue => e
      results[:error] = e.message
    end

    results
  end
end

# Set up monitoring
# Nagios, DataDog, or other monitoring
results = EncryptionHealthCheck.check
if results[:configuration_valid] && results[:sample_encrypt_decrypt]
  exit 0  # OK
else
  puts "Encryption health check failed: #{results}"
  exit 2  # Critical
end
```

### Backup and Recovery

```ruby
# Backup encryption keys securely
class EncryptionKeyBackup
  def self.backup_keys_to_vault
    keys = Familia.config.encryption_keys

    keys.each do |version, key|
      # Store in HashiCorp Vault, AWS KMS, etc.
      VaultClient.store_secret(
        path: "familia/encryption_keys/#{version}",
        data: { key: key },
        lease_duration: '8760h'  # 1 year
      )
    end
  end

  def self.restore_keys_from_vault
    versions = VaultClient.list_secrets('familia/encryption_keys/')

    restored_keys = {}
    versions.each do |version|
      secret = VaultClient.read_secret("familia/encryption_keys/#{version}")
      restored_keys[version.to_sym] = secret['key']
    end

    restored_keys
  end
end
```

---

## See Also

- **[Overview](../overview.md#encrypted-fields)** - Conceptual introduction to encrypted fields
- **[Technical Reference](../reference/api-technical.md#encrypted-fields-feature-v200-pre5)** - Implementation details and advanced patterns
- **[Security Model Guide](security-model.md)** - Cryptographic design and threat model considerations
- **[Feature System Guide](feature-system.md)** - Understanding Familia's feature architecture
- **[Implementation Guide](implementation.md)** - Production deployment and configuration patterns
