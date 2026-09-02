# try/features/encryption/encrypted_data_valid_logging_try.rb
#
# frozen_string_literal: true

# EncryptedData.valid? runs on every assignment to an encrypted field, so the
# candidate it inspects is usually the plaintext the application just supplied.
# Its debug output must never echo that candidate back into the log - neither
# the parsed value (a plaintext that happens to be a JSON object) nor the JSON
# parser's complaint about it (which can quote the offending input).
# See: https://github.com/delano/familia/issues/406

require_relative '../../support/helpers/test_helpers'
require_relative '../../../lib/familia/encryption'
require 'base64'
require 'stringio'

# Runs the block with Familia.debug enabled and the logger swapped for one that
# writes to a StringIO (reassigning $stderr does not work -- the logger memoizes
# its stream). Restores both afterwards and returns everything that was logged.
def capture_valid_debug_output
  captured = StringIO.new
  original_logger = Familia.logger
  original_debug = Familia.debug?
  Familia.logger = Familia::FamiliaLogger.new(captured)
  Familia.debug = true
  begin
    yield
  ensure
    Familia.debug = original_debug
    Familia.logger = original_logger
  end
  captured.string
end

# A plaintext that parses as a JSON object, with distinctive markers in both a
# key and the values so any echo of either is detectable.
@sensitive_json = '{"ssn":"123-45-6789","note":"top-secret-marker"}'

# A plaintext that is not JSON at all.
@plain_secret = 'plain-secret-marker-xyz'

# A structurally complete envelope (valid? only checks the required keys).
@full_envelope = Familia::JsonSerializer.dump(
  algorithm: 'xchacha20poly1305',
  nonce: Base64.strict_encode64('n' * 24),
  ciphertext: Base64.strict_encode64('c' * 32),
  auth_tag: Base64.strict_encode64('t' * 16),
  key_version: 'v1',
)

# The same envelope with one required key removed.
@partial_envelope = Familia::JsonSerializer.dump(
  algorithm: 'xchacha20poly1305',
  nonce: Base64.strict_encode64('n' * 24),
  ciphertext: Base64.strict_encode64('c' * 32),
  key_version: 'v1',
)

## A JSON-object plaintext is not a valid envelope
Familia::Encryption::EncryptedData.valid?(@sensitive_json)
#=> false

## Debug logging is active while validating a JSON-object plaintext
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@sensitive_json)
end
output.include?('[valid?]')
#=> true

## Debug output does not echo the JSON-object plaintext values
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@sensitive_json)
end
[output.include?('123-45-6789'), output.include?('top-secret-marker')]
#=> [false, false]

## Debug output does not echo the JSON-object plaintext key names either
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@sensitive_json)
end
output.include?('ssn')
#=> false

## A non-JSON plaintext is not a valid envelope
Familia::Encryption::EncryptedData.valid?(@plain_secret)
#=> false

## Non-JSON plaintext logs the parser error class without the plaintext
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@plain_secret)
end
[output.include?('[valid?] JSON error: Familia::SerializerError'), output.include?(@plain_secret)]
#=> [true, false]

## Non-JSON plaintext log line carries only the exception class
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@plain_secret)
end
output[/\[valid\?\] JSON error: [^\n]*/]
#=> "[valid?] JSON error: Familia::SerializerError"

## An envelope with every required field is valid
Familia::Encryption::EncryptedData.valid?(@full_envelope)
#=> true

## A complete envelope logs an empty missing list
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@full_envelope)
end
output[/\[valid\?\] result: [^\n]*/]
#=> "[valid?] result: true, missing: []"

## An envelope without auth_tag is not valid
Familia::Encryption::EncryptedData.valid?(@partial_envelope)
#=> false

## An incomplete envelope names the missing required field
output = capture_valid_debug_output do
  Familia::Encryption::EncryptedData.valid?(@partial_envelope)
end
output[/\[valid\?\] result: [^\n]*/]
#=> "[valid?] result: false, missing: [:auth_tag]"

## Debug flag and logger are restored after capture
before = [Familia.debug?, Familia.logger]
capture_valid_debug_output { Familia::Encryption::EncryptedData.valid?(@full_envelope) }
[Familia.debug?, Familia.logger] == before
#=> true
