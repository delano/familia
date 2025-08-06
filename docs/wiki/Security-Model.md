# Security Model

## Cryptographic Design

### Encryption Algorithms

**Primary (with libsodium):**
- Algorithm: XChaCha20-Poly1305
- Key Size: 256 bits
- Nonce Size: 192 bits
- Authentication Tag: 128 bits

**Fallback (with OpenSSL):**
- Algorithm: AES-256-GCM
- Key Size: 256 bits
- IV Size: 96 bits
- Authentication Tag: 128 bits

### Key Derivation

Each field gets a unique key derived from the master key:

```
Field Key = KDF(Master Key, Context)

Where Context = "ClassName:field_name:record_identifier"
```

**KDF Functions:**
- Libsodium: BLAKE2b with personalization
- OpenSSL: HKDF-SHA256

### Ciphertext Format

```json
{
  "library": "libsodium",
  "algorithm": "xchacha20poly1305",
  "nonce": "base64_encoded_nonce",
  "ciphertext": "base64_encoded_ciphertext",
  "key_version": "v1_2504"
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

**With libsodium:**
- Automatic zeroing of sensitive memory
- Constant-time comparisons
- Protected memory pages when available

**Without libsodium:**
- Warning logged about reduced security
- Ruby GC may retain plaintext copies
- Timing attacks theoretically possible

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
