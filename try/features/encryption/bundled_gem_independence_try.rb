# try/features/encryption/bundled_gem_independence_try.rb
#
# frozen_string_literal: true

# Familia::Encryption must work without the base64 and benchmark gems.
# Ruby 3.4.0's NEWS lists base64, and Ruby 4.0.0's NEWS lists benchmark,
# under "The following bundled gems are promoted from default gems.", so
# under Bundler each loads only when the application's bundle contains it.
# familia declares neither. It encodes with core Array#pack and
# String#unpack1 (Familia::Encryption::StrictBase64) and times
# Encryption.benchmark with Process.clock_gettime.
#
# Each case runs in a fresh Ruby process and inspects $LOADED_FEATURES
# there. This process cannot answer the question: other tryouts require
# base64 and benchmark, and the development bundle contains both. The child
# inherits Bundler's environment, so it resolves gems from the same bundle.

require_relative '../../support/helpers/test_helpers'
require_relative '../../support/helpers/fresh_ruby'

## require 'familia' does not load base64
run_fresh_ruby(<<~RUBY)
  require 'familia'
  puts $LOADED_FEATURES.any? { |path| File.basename(path) == 'base64.rb' }
RUBY
#=> ['false']

## Encrypt, decrypt and envelope validation work without loading base64
run_fresh_ruby(<<~RUBY)
  require 'familia'
  require 'securerandom'
  Familia.config.encryption_keys = { v1: SecureRandom.base64(32) }
  Familia.config.current_key_version = :v1
  Familia::Encryption.validate_configuration!
  envelope = Familia::Encryption.encrypt('secret text', context: 'probe:ctx')
  data = Familia::Encryption::EncryptedData.from_json(envelope)
  data.validate_decryptable!
  puts data.decryptable?
  puts Familia::Encryption.decrypt(envelope, context: 'probe:ctx')
  puts $LOADED_FEATURES.any? { |path| File.basename(path) == 'base64.rb' }
RUBY
#=> ['true', 'secret text', 'false']

## Malformed Base64 in a key or an envelope still raises EncryptionError
run_fresh_ruby(<<~RUBY)
  require 'familia'
  require 'securerandom'
  Familia.config.encryption_keys = { v1: 'not base64!' }
  Familia.config.current_key_version = :v1
  begin
    Familia::Encryption.validate_configuration!
  rescue Familia::EncryptionError => e
    puts e.message
  end
  Familia.config.encryption_keys = { v1: SecureRandom.base64(32) }
  envelope = Familia::JsonSerializer.parse(Familia::Encryption.encrypt('x', context: 'c'))
  envelope['nonce'] = 'not base64!'
  tampered = Familia::JsonSerializer.dump(envelope)
  puts Familia::Encryption::EncryptedData.from_json(tampered).decryptable?
  begin
    Familia::Encryption.decrypt(tampered, context: 'c')
  rescue Familia::EncryptionError => e
    puts e.message
  end
  puts $LOADED_FEATURES.any? { |path| File.basename(path) == 'base64.rb' }
RUBY
#=> ['Current encryption key is not valid Base64', 'false', 'Invalid Base64 encoding in nonce field', 'false']

## Encryption.benchmark times each provider without loading benchmark
run_fresh_ruby(<<~RUBY)
  require 'familia'
  require 'securerandom'
  Familia.config.encryption_keys = { v1: SecureRandom.base64(32) }
  Familia.config.current_key_version = :v1
  Familia::Encryption.validate_configuration!
  results = Familia::Encryption.benchmark(iterations: 2)
  puts results.key?('aes-256-gcm')
  puts results.values.all? { |r| r[:time].is_a?(Float) && r[:time].positive? && r[:ops_per_sec].positive? }
  puts $LOADED_FEATURES.any? { |path| File.basename(path) == 'benchmark.rb' }
RUBY
#=> ['true', 'true', 'false']

## StrictBase64 matches the base64 gem's strict methods byte for byte
require 'base64'
bytes = (0..255).map(&:chr).join.b * 3
[
  Familia::Encryption::StrictBase64.encode(bytes) == Base64.strict_encode64(bytes),
  Familia::Encryption::StrictBase64.decode(Base64.strict_encode64(bytes)) == bytes,
]
#=> [true, true]

## StrictBase64.decode rejects input the base64 gem's strict decoder rejects
%W[MDEyMzQ1Njc MDEyMzQ1Njc== MDEy\nMzQ1Njc= - _].map do |text|
  begin
    Familia::Encryption::StrictBase64.decode(text)
    :accepted
  rescue ArgumentError
    :rejected
  end
end
#=> [:rejected, :rejected, :rejected, :rejected, :rejected]
