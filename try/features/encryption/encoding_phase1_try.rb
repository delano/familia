# try/features/encryption/encoding_phase1_try.rb
#
# frozen_string_literal: true

# Phase 1: Defensive read -- filter unknown keys, default encoding to UTF-8 on decrypt
# See: https://github.com/delano/familia/issues/228

require_relative '../../support/helpers/test_helpers'
require_relative '../../../lib/familia/encryption'
require 'base64'

## Decrypted value has UTF-8 encoding (not ASCII-8BIT)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "hello world"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
decrypted = Familia::Encryption.decrypt(encrypted, context: context)
decrypted.encoding.to_s
#=> "UTF-8"

## Round-trip preserves encoding through encrypt then decrypt
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "caf\u00e9 na\u00efve r\u00e9sum\u00e9"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
decrypted = Familia::Encryption.decrypt(encrypted, context: context)
[decrypted, decrypted.encoding.to_s]
#=> ["caf\u00e9 na\u00efve r\u00e9sum\u00e9", "UTF-8"]

## from_json handles payloads with extra unknown keys without raising
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "unknown keys test"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Parse, inject unknown keys, re-serialize
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:future_field] = "something new"
parsed[:version] = 99
json_with_extras = Familia::JsonSerializer.dump(parsed)

# Should decrypt without error, ignoring unknown keys
decrypted = Familia::Encryption.decrypt(json_with_extras, context: context)
decrypted
#=> "unknown keys test"

## from_json handles Hash input with extra unknown keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "hash extra keys"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Parse into hash, add unknown keys, pass hash directly
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:unknown_extra] = "ignored"
data = Familia::Encryption::EncryptedData.from_json(parsed)
data.algorithm
#=> "xchacha20poly1305"

## from_json handles payloads missing the encoding key (backward compat)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

# Simulate a pre-Phase-2 envelope by constructing one without encoding
legacy_hash = {
  algorithm: "xchacha20poly1305",
  nonce: Base64.strict_encode64('n' * 24),
  ciphertext: Base64.strict_encode64('c' * 32),
  auth_tag: Base64.strict_encode64('t' * 16),
  key_version: "v1"
}
data = Familia::Encryption::EncryptedData.from_json(legacy_hash)
data.encoding
#=> nil

## Decryption of legacy envelope (no encoding key) defaults to UTF-8
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "legacy payload"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Simulate a legacy envelope that definitely has no encoding key
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed.delete(:encoding)
legacy_json = Familia::JsonSerializer.dump(parsed)

decrypted = Familia::Encryption.decrypt(legacy_json, context: context)
[decrypted, decrypted.encoding.to_s]
#=> ["legacy payload", "UTF-8"]

## EncryptedData encoding field defaults to nil when not provided
data = Familia::Encryption::EncryptedData.new(
  algorithm: "test",
  nonce: "nonce",
  ciphertext: "ct",
  auth_tag: "tag",
  key_version: "v1"
)
data.encoding
#=> nil

## EncryptedData accepts encoding when provided
data = Familia::Encryption::EncryptedData.new(
  algorithm: "test",
  nonce: "nonce",
  ciphertext: "ct",
  auth_tag: "tag",
  key_version: "v1",
  encoding: "ISO-8859-1"
)
data.encoding
#=> "ISO-8859-1"

## to_h omits encoding when nil (envelope stays clean)
data = Familia::Encryption::EncryptedData.new(
  algorithm: "test",
  nonce: "nonce",
  ciphertext: "ct",
  auth_tag: "tag",
  key_version: "v1"
)
data.to_h.key?(:encoding)
#=> false

## to_h includes encoding when explicitly set
data = Familia::Encryption::EncryptedData.new(
  algorithm: "test",
  nonce: "nonce",
  ciphertext: "ct",
  auth_tag: "tag",
  key_version: "v1",
  encoding: "UTF-8"
)
data.to_h.key?(:encoding)
#=> true

## to_h compact output serializes to JSON without encoding null
data = Familia::Encryption::EncryptedData.new(
  algorithm: "test",
  nonce: "nonce",
  ciphertext: "ct",
  auth_tag: "tag",
  key_version: "v1"
)
json = Familia::JsonSerializer.dump(data.to_h)
json.include?('"encoding"')
#=> false

## Future envelope with encoding key present decrypts with specified encoding
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "future format"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Simulate a future writer that includes encoding in the envelope
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding] = "UTF-8"
future_json = Familia::JsonSerializer.dump(parsed)

decrypted = Familia::Encryption.decrypt(future_json, context: context)
[decrypted, decrypted.encoding.to_s]
#=> ["future format", "UTF-8"]

## Future envelope with encoding and extra unknown keys decrypts correctly
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "full future envelope"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Simulate a future writer with encoding, compression, and version fields
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding] = "UTF-8"
parsed[:compression] = "zstd"
parsed[:envelope_version] = 2
future_json = Familia::JsonSerializer.dump(parsed)

decrypted = Familia::Encryption.decrypt(future_json, context: context)
decrypted
#=> "full future envelope"

## validate! filters unknown keys from JSON string input
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "validate filter test"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Add unknown keys, run through validate! directly
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:compression] = "gzip"
parsed[:metadata] = { created_at: "2026-01-01" }
json_with_extras = Familia::JsonSerializer.dump(parsed)

data = Familia::Encryption::EncryptedData.validate!(json_with_extras)
[data.class, data.encoding]
#=> [Familia::Encryption::EncryptedData, "UTF-8"]

## from_json handles Hash with string keys and unknown extras
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "string keys test"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Build a string-keyed hash with extra keys (simulating external deserialization)
parsed = Familia::JsonSerializer.parse(encrypted) # no symbolize_names
parsed["unknown_key"] = "should be ignored"
data = Familia::Encryption::EncryptedData.from_json(parsed)
data.algorithm
#=> "xchacha20poly1305"

## from_json Hash path without encoding key defaults encoding to nil
# Simulate a pre-Phase-2 envelope by constructing one without encoding
legacy_hash = {
  algorithm: "xchacha20poly1305",
  nonce: Base64.strict_encode64('n' * 24),
  ciphertext: Base64.strict_encode64('c' * 32),
  auth_tag: Base64.strict_encode64('t' * 16),
  key_version: "v1"
}
data = Familia::Encryption::EncryptedData.from_json(legacy_hash)
data.encoding
#=> nil

## valid? returns true for envelopes with extra unknown keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "valid check"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Add extra keys to the JSON
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:future_field] = "extra"
parsed[:encoding] = "UTF-8"
json_with_extras = Familia::JsonSerializer.dump(parsed)

Familia::Encryption::EncryptedData.valid?(json_with_extras)
#=> true

## Decrypt of empty string returns nil without error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
Familia::Encryption.decrypt("", context: context)
#=> nil

## Non-UTF-8 encoding in envelope is applied on decrypt
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "caf\u00e9"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Simulate a Phase 2 writer that records the original encoding
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding] = "ISO-8859-1"
future_json = Familia::JsonSerializer.dump(parsed)

decrypted = Familia::Encryption.decrypt(future_json, context: context)
[decrypted.encoding.to_s, decrypted.bytes == plaintext.bytes]
#=> ["ISO-8859-1", true]

## Decrypt of nil returns nil without error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
Familia::Encryption.decrypt(nil, context: context)
#=> nil

## Bogus encoding name in envelope raises EncryptionError
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "bad encoding test"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Inject an invalid encoding name into the envelope
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding] = "NOT-A-REAL-ENCODING"
tampered_json = Familia::JsonSerializer.dump(parsed)

begin
  Familia::Encryption.decrypt(tampered_json, context: context)
  "should have raised"
rescue Familia::Encryption::EncryptionError => e
  e.message
end
#=~ /Decryption failed/

## Binary data round-trip preserves bytes when encoding is set to ASCII-8BIT
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "binary\x00payload\xFF".b

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Simulate a Phase 2 writer that records ASCII-8BIT for binary content
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding] = "ASCII-8BIT"
future_json = Familia::JsonSerializer.dump(parsed)

decrypted = Familia::Encryption.decrypt(future_json, context: context)
[decrypted.encoding.to_s, decrypted.bytes == plaintext.bytes]
#=> ["ASCII-8BIT", true]

## Multibyte UTF-8 content round-trips with correct encoding and byte count
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "\u{1F600}\u{1F389}\u{2764}"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
decrypted = Familia::Encryption.decrypt(encrypted, context: context)
[decrypted == plaintext, decrypted.encoding.to_s, decrypted.valid_encoding?]
#=> [true, "UTF-8", true]

# TEARDOWN
Fiber[:familia_key_cache]&.clear if Fiber[:familia_key_cache]
