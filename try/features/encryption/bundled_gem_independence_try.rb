# try/features/encryption/bundled_gem_independence_try.rb
#
# frozen_string_literal: true

# Familia::Encryption must work without the base64 gem. Ruby 3.4.0's NEWS
# lists base64 under "The following bundled gems are promoted from default
# gems.", so under Bundler it loads only when the application's bundle
# contains it. familia does not declare it, and encodes with core
# Array#pack and String#unpack1 instead (Familia::Encryption::StrictBase64).
#
# Each case runs in a fresh Ruby process and inspects $LOADED_FEATURES
# there. This process cannot answer the question: other tryouts require
# base64, and the development bundle contains it. The child inherits
# Bundler's environment, so it resolves gems from the same bundle.

require 'open3'
require 'rbconfig'
require_relative '../../support/helpers/test_helpers'

@lib_dir = File.expand_path('../../../lib', __dir__)

# Runs code in a fresh Ruby process with this checkout's lib/ first on the
# load path and returns its output lines, stripped.
def run_fresh_ruby(code)
  out, status = Open3.capture2e(RbConfig.ruby, '-I', @lib_dir, '-e', code)
  raise "fresh ruby exited #{status.exitstatus}:\n#{out}" unless status.success?

  out.lines.map(&:strip)
end

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
