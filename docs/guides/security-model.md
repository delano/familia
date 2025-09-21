# Security Model

## Cryptographic Design

### Provider-Based Architecture

Familia uses a modular provider system that automatically selects the best available encryption algorithm:

### Encryption Algorithms

**XChaCha20-Poly1305 Provider (Priority: 100)**
- Requires: `rbnacl` gem (libsodium bindings)
- Key Size: 256 bits (32 bytes)
- Nonce Size: 192 bits (24 bytes) - extended nonce space
- Authentication Tag: 128 bits (16 bytes)
- Key Derivation: BLAKE2b with personalization string

**AES-256-GCM Provider (Priority: 50)**
- Requires: OpenSSL (always available)
- Key Size: 256 bits (32 bytes)
- Nonce Size: 96 bits (12 bytes) - standard GCM nonce
- Authentication Tag: 128 bits (16 bytes)
- Key Derivation: HKDF-SHA256

### Key Derivation

Each field gets a unique key derived from the master key:

```
Field Key = KDF(Master Key, Context)

Where Context = "ClassName:field_name:record_identifier"
```

**Provider-Specific KDF:**
- **XChaCha20-Poly1305**: BLAKE2b with customizable personalization string
- **AES-256-GCM**: HKDF-SHA256 with salt and info parameters

The personalization string provides cryptographic domain separation:
```ruby
Familia.configure do |config|
  config.encryption_personalization = 'MyApp-2024'  # Default: 'Familia'
end
```

### Ciphertext Format

The encrypted data is stored as JSON with algorithm-specific fields:

**XChaCha20-Poly1305:**
```json
{
  "algorithm": "xchacha20poly1305",
  "nonce": "base64_24_byte_nonce",
  "ciphertext": "base64_encrypted_data",
  "auth_tag": "base64_16_byte_tag",
  "key_version": "v1"
}
```

**AES-256-GCM:**
```json
{
  "algorithm": "aes-256-gcm",
  "nonce": "base64_12_byte_iv",
  "ciphertext": "base64_encrypted_data",
  "auth_tag": "base64_16_byte_tag",
  "key_version": "v1"
}
```

## Threat Model

### Protected Against

#### Database Compromise
- All sensitive fields encrypted with strong keys
- Attackers see only ciphertext

#### Field Value Swapping
- Field-specific key derivation prevents cross-field decryption
- Swapped values fail to decrypt

#### Replay Attacks
- Each encryption uses unique random nonce
- Old values remain valid but are distinct encryptions

#### Tampering
- Authenticated encryption (Poly1305/GCM)
- Modified ciphertext fails authentication

### Not Protected Against

#### Application Memory Compromise
- Plaintext values exist in Ruby memory
- Mitigation: Use libsodium for memory wiping, minimize plaintext lifetime

#### Master Key Compromise
- All encrypted data compromised if keys obtained
- Mitigation: Secure key storage, regular rotation, hardware security modules

#### Side-Channel Attacks
- Key recovery through timing/power analysis
- Mitigation: Libsodium provides constant-time operations

## Additional Security Features

### Passphrase Protection

For ultra-sensitive fields, add user passphrases:

```ruby
encrypted_field :love_letter

# Passphrase required for decryption
vault.love_letter(passphrase_value: user_passphrase)
```

**How it works:**
1. Passphrase hashed with SHA-256
2. Hash included in Additional Authenticated Data (AAD)
3. Wrong passphrase = authentication failure
4. Passphrase never stored, only verified

### Memory Safety

**⚠️ Critical Ruby Memory Limitations:**

Ruby provides **NO** memory safety guarantees for cryptographic secrets. This affects ALL providers:

- **No secure memory wiping**: Ruby cannot guarantee memory zeroing
- **GC copying**: Garbage collector may copy secrets before cleanup
- **String operations**: Every `.dup`, `+`, or interpolation creates uncontrolled copies
- **Memory dumps**: Secrets may persist in swap files or core dumps
- **Finalizer uncertainty**: `ObjectSpace.define_finalizer` timing is unpredictable

**Provider-Specific Mitigations:**

Both providers attempt best-effort memory clearing:
- Call `.clear` on sensitive strings after use
- UnsortedSet variables to `nil` when done
- Use finalizers for cleanup (no guarantees)

**Recommendation**: For production systems with high-security requirements, consider:
- Hardware Security Modules (HSMs)
- External key management services
- Languages with manual memory management (C, Rust)
- Cryptographic appliances with secure enclaves

### RedactedString

Prevents accidental logging of sensitive data:

```ruby
class RedactedString < String
  def to_s
    '[REDACTED]'
  end

  def inspect
    '[REDACTED]'
  end
end

# In logs:
logger.info "Love letter: #{user.love_letter}"  # => "Love letter: [REDACTED]"
```

## Security Checklist

### Development

- [ ] Never log plaintext sensitive fields
- [ ] Use RedactedString for extra protection
- [ ] Use libsodium for production when possible
- [ ] Validate encryption at startup
- [ ] Test encryption round-trips

### Operations

- [ ] Regular key rotation schedule
- [ ] Monitor decryption failures
- [ ] Log field access patterns for auditing purposes
