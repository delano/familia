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
  "key_version": "v1"
}
```

## Threat Model

### Protected Against ✅

#### 1. Database Compromise
- **Threat**: Attacker gains access to Redis/Valkey
- **Protection**: All sensitive fields encrypted with strong keys
- **Impact**: Attacker sees only ciphertext

#### 2. Field Value Swapping
- **Threat**: Attacker tries to swap encrypted values between fields
- **Protection**: Field-specific key derivation prevents cross-field decryption
- **Impact**: Swapped values fail to decrypt

#### 3. Replay Attacks
- **Threat**: Attacker replays old encrypted values
- **Protection**: Each encryption uses unique random nonce
- **Impact**: Old values remain valid but are distinct encryptions

#### 4. Tampering
- **Threat**: Attacker modifies ciphertext
- **Protection**: Authenticated encryption (Poly1305/GCM)
- **Impact**: Modified ciphertext fails authentication

### Not Protected Against ❌

#### 1. Application Memory Compromise
- **Threat**: Attacker gains memory access
- **Risk**: Plaintext values exist in Ruby memory
- **Mitigation**: Use libsodium for memory wiping, minimize plaintext lifetime

#### 2. Master Key Compromise
- **Threat**: Attacker obtains encryption keys
- **Risk**: All encrypted data compromised
- **Mitigation**: Secure key storage, regular rotation, hardware security modules

#### 3. Side-Channel Attacks
- **Threat**: Timing/power analysis attacks
- **Risk**: Key recovery through side channels
- **Mitigation**: Libsodium provides constant-time operations

## Additional Security Features

### Passphrase Protection

For ultra-sensitive fields, add user passphrases:

```ruby
encrypted_field :nuclear_codes

# Passphrase required for decryption
vault.nuclear_codes(passphrase_value: user_passphrase)
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
logger.info "User SSN: #{user.ssn}"  # => "User SSN: [REDACTED]"
```

## Security Checklist

### Development

- [ ] Never log plaintext sensitive fields
- [ ] Use RedactedString for extra protection
- [ ] Enable libsodium for production
- [ ] Validate encryption at startup
- [ ] Test encryption round-trips

### Operations

- [ ] Secure key generation (256 bits minimum)
- [ ] Environment variable or secret manager for keys
- [ ] Regular key rotation schedule
- [ ] Monitor decryption failures
- [ ] Audit field access patterns

### Key Storage Best Practices

**Good:**
- Environment variables (for simple deployments)
- Secret management services (AWS Secrets Manager, Vault)
- Hardware Security Modules (HSMs)

**Bad:**
- Hardcoded in source code
- Configuration files in repository
- Unencrypted files on disk

## Compliance Considerations

### GDPR/CCPA
- Encrypted fields help meet "appropriate security" requirements
- Supports data minimization (only decrypt when needed)
- Enables secure data deletion (destroy keys)

### PCI DSS
- Meets encryption requirements for cardholder data
- Provides key management capabilities
- Supports audit logging

### HIPAA
- Appropriate for PHI encryption at rest
- Supports access controls via passphrase protection
- Enables audit trails

## Security Warnings

⚠️ **Ruby Memory Management**
- Ruby doesn't guarantee memory clearing
- GC may create copies of plaintext
- Consider process isolation for highly sensitive data

⚠️ **OpenSSL Fallback**
- Less resistant to side-channel attacks
- No automatic memory wiping
- Strongly recommend libsodium for production

⚠️ **Key Rotation Complexity**
- Passphrase-protected fields need user interaction
- Plan rotation strategy before deployment
- Test rotation procedures regularly
