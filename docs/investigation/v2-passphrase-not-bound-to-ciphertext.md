# Discovery: v2 passphrase is not cryptographically bound to ciphertext

Date: 2026-06-01
Familia version: 2.9.1
Proof: `try/features/encrypted_fields/aad_transient_proof_try.rb` (14/14 pass)

## Context

Before Familia v2, the OTS codebase included the passphrase in the encryption key. The question is whether the v2 migration preserved this property. (Spoiler: no.)

## What `secret.rb` declares

```ruby
encrypted_field :ciphertext
transient_field :ciphertext_passphrase
transient_field :ciphertext_domain
```

`encrypted_field :ciphertext` has no `aad_fields:` option. The transient fields are declared but not referenced by the encrypted field.

## How Familia v2 encryption derives its key and AAD

`EncryptedFieldType#encrypt_value` (encrypted_field_type.rb:127-131):

```ruby
def encrypt_value(record, value)
  context = build_context(record)
  additional_data = build_aad(record)
  Familia::Encryption.encrypt(value, context: context, additional_data: additional_data)
end
```

`build_context` (encrypted_field_type.rb:164-166):

```ruby
def build_context(record)
  "#{record.class.name}:#{@name}:#{record.identifier}"
end
```

`build_aad` with no `aad_fields` (encrypted_field_type.rb:211-222):

```ruby
def build_aad(record)
  identifier = record.identifier
  return nil if identifier.nil? || identifier.to_s.empty?
  base_components = [record.class.name, @name, identifier]
  if @aad_fields.empty?
    base_components.join(':')
  else
    # ...
  end
end
```

Neither `build_context` nor `build_aad` references the passphrase. The encryption key is derived from the master key, class name, field name, and record identifier.

## How the passphrase is actually used in v2

`spawn_pair` (receipt.rb:205-226):

```ruby
def spawn_pair(owner_id, lifespan, content, passphrase: nil, domain: nil, kind: nil)
  secret = Onetime::Secret.new(owner_id: owner_id)
  # ...
  secret.ciphertext = content              # encrypts without passphrase involvement

  unless passphrase.to_s.empty?
    secret.update_passphrase passphrase     # stores argon2 hash separately
    receipt.has_passphrase = true
  end
  # ...
end
```

`update_passphrase` (legacy_encrypted_fields.rb:177-189):

```ruby
def update_passphrase(val, algorithm: :argon2)
  case algorithm
  when :argon2
    self.passphrase_encryption = '2'
    self.passphrase = ::Argon2::Password.create(val, argon2_hash_cost)
  when :bcrypt
    self.passphrase_encryption = '1'
    self.passphrase = BCrypt::Password.create(val, cost: 12).to_s
  end
  self
end
```

The passphrase is hashed (argon2 or bcrypt) and stored as a separate field. It is checked as an app-layer gate before revealing the secret. It is not part of the encryption key derivation or AAD.

`decrypted_secret_value` (secret.rb:94-101):

```ruby
def decrypted_secret_value(passphrase_input: nil)
  if !ciphertext.to_s.empty?
    ciphertext.reveal { it }&.force_encoding('utf-8')
  elsif !value_encryption.to_s.empty?
    @passphrase_temp = passphrase_input.to_s.empty? ? nil : passphrase_input
    decrypted_value
  end
end
```

For v2 secrets (`ciphertext` present), the passphrase_input parameter is not used. `ciphertext.reveal` decrypts using only the master key and record context.

## v1 vs v2

In v1 (`LegacyEncryptedFields`), the passphrase was incorporated into the encryption key. The privacy claim was cryptographically true.

In v2 (`Familia::Features::EncryptedFields`), the passphrase is an access-control gate only. Anyone with the master encryption key can decrypt any v2 secret without the passphrase.

## The `transient_field` + `aad_fields` interaction problem

Even if `aad_fields: [:ciphertext_passphrase]` were added to the encrypted_field declaration, it would not work as expected.

`build_aad` with `aad_fields` (encrypted_field_type.rb:232-236):

```ruby
values = @aad_fields.map { |field| record.send(field).to_s }
all_components = [*base_components, *values]
Digest::SHA256.hexdigest(all_components.join(':'))
```

Transient field getters return `RedactedString` objects. `RedactedString#to_s` (redacted_string.rb:142):

```ruby
def to_s = '[REDACTED]'
```

This means `record.send(:ciphertext_passphrase).to_s` returns `"[REDACTED]"` regardless of the actual passphrase value. All non-nil transient field values produce identical AAD.

The proof demonstrates:
- Two different passphrases (`'passphrase-one'` and `'completely-different-passphrase'`) produce identical `build_aad` output
- Changing a transient field value after encryption does not break decryption
- The only differentiation is nil vs non-nil (nil.to_s returns `""`, RedactedString.to_s returns `"[REDACTED]"`)

To make transient fields work as AAD, `build_aad` would need to call `.value` or `.expose` on `RedactedString` instead of `.to_s`. This is a Familia-level change.

## Test results

```
14 testcases passed, 0 failed in 1 files (807ms)
```

| Test | Expected | Result |
|------|----------|--------|
| No-AAD: decrypt succeeds without passphrase (current OTS) | `"Attack at dawn"` | pass |
| No-AAD: transient passphrase is nil after reload | `true` | pass |
| No-AAD: transient domain is nil after reload | `true` | pass |
| Field-AAD: encrypt/decrypt with matching email | `"Bound to alice"` | pass |
| Field-AAD: changing email after encryption breaks decrypt | `"EncryptionError"` | pass |
| Field-AAD: save/reload with matching field succeeds | `"Survives reload"` | pass |
| Transient-AAD: RedactedString.to_s returns [REDACTED] | `"[REDACTED]"` | pass |
| Transient-AAD: different passphrases produce identical AAD | `true` | pass |
| Transient-AAD: changing passphrase after encrypt does NOT break decrypt | `"Should be bound but is not"` | pass |
| Transient-AAD: nil vs set does differ (1-bit) | `false` | pass |
| Transient-AAD: encrypt with passphrase, clear to nil, decrypt fails | `"EncryptionError"` | pass |
| Field-AAD: swapping two values breaks decrypt | `"EncryptionError"` | pass |
| Field-AAD: missing one of two fields breaks decrypt | `"EncryptionError"` | pass |
| Field-AAD: different emails produce different AAD | `false` | pass |
