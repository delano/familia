# try/features/encryption/encoding_phase2_try.rb
#
# frozen_string_literal: true

# Phase 2: Write encoding on encrypt -- the encrypt method now includes
# encoding: plaintext.encoding.name in the EncryptedData envelope.
# See: https://github.com/delano/familia/issues/229

require_relative '../../support/helpers/test_helpers'
require_relative '../../../lib/familia/encryption'
require 'base64'

## Encrypted payload includes encoding key
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "hello world"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed.key?(:encoding)
#=> true

## Encoding value matches plaintext encoding for UTF-8 string
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "hello world"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding]
#=> "UTF-8"

## ISO-8859-1 encoding captured correctly
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "caf\u00e9".encode("ISO-8859-1")

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding]
#=> "ISO-8859-1"

## ASCII-8BIT (binary) encoding captured
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "binary\x00\xFF".b

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed[:encoding]
#=> "ASCII-8BIT"

## Round-trip preserves UTF-8 encoding
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "caf\u00e9 na\u00efve r\u00e9sum\u00e9"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
decrypted = Familia::Encryption.decrypt(encrypted, context: context)
[decrypted == plaintext, decrypted.encoding.to_s]
#=> [true, "UTF-8"]

## Round-trip preserves non-UTF-8 encoding
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "caf\u00e9".encode("ISO-8859-1")

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
decrypted = Familia::Encryption.decrypt(encrypted, context: context)
[decrypted.encoding.to_s, decrypted.bytes == plaintext.bytes]
#=> ["ISO-8859-1", true]

## Legacy envelopes without encoding still decrypt to UTF-8
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "legacy payload"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context)

# Strip the encoding key to simulate a Phase 1 (or older) envelope
parsed = Familia::JsonSerializer.parse(encrypted, symbolize_names: true)
parsed.delete(:encoding)
legacy_json = Familia::JsonSerializer.dump(parsed)

decrypted = Familia::Encryption.decrypt(legacy_json, context: context)
[decrypted, decrypted.encoding.to_s]
#=> ["legacy payload", "UTF-8"]

# TEARDOWN
Fiber[:familia_key_cache]&.clear if Fiber[:familia_key_cache]
