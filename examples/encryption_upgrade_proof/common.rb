# examples/encryption_upgrade_proof/common.rb
#
# frozen_string_literal: true

# Shared fixtures and a micro assertion harness for the encryption upgrade
# proof phases. Each phase runs in its own process under its own Gemfile
# (see run.sh), so this file is loaded fresh per phase.

require 'json'
require 'base64'
require 'digest'
require 'openssl'
require 'fileutils'
require 'familia'

module Proof
  STATE_DIR = ENV['PROOF_STATE_DIR'] || File.join(__dir__, 'state')

  # Mirrors how onetimesecret derives its Familia master keys
  # (lib/onetime/initializers/configure_familia.rb): v1 is the legacy
  # SHA-256 digest of the site secret, v2 is HKDF-derived. Both are
  # base64-encoded 32-byte keys.
  SITE_SECRET = 'proof-fixture-site-secret'
  V1_KEY = Base64.strict_encode64(Digest::SHA256.digest(SITE_SECRET))
  V2_KEY = Base64.strict_encode64(
    OpenSSL::KDF.hkdf(SITE_SECRET, salt: 'proof-fixture', info: 'familia_enc', length: 32, hash: 'SHA256')
  )

  @checks = []

  module_function

  def configure!(current: :v2)
    Familia.config.encryption_keys = { v1: V1_KEY, v2: V2_KEY }
    Familia.config.current_key_version = current
  end

  def save_state(name, data)
    FileUtils.mkdir_p(STATE_DIR)
    File.write(File.join(STATE_DIR, "#{name}.json"), JSON.pretty_generate(data))
  end

  def load_state(name)
    JSON.parse(File.read(File.join(STATE_DIR, "#{name}.json")))
  end

  # Expect the block to return a truthy value.
  def check(desc)
    result = yield
    record(desc, !!result, result.inspect)
  rescue StandardError => e
    record(desc, false, "#{e.class}: #{e.message}")
  end

  # Expect the block to raise error_class (optionally matching message_pattern).
  def check_raises(desc, error_class, message_pattern = nil)
    yield
    record(desc, false, 'no exception raised')
  rescue error_class => e
    if message_pattern && e.message !~ message_pattern
      record(desc, false, "raised #{error_class} but message #{e.message.inspect} !~ #{message_pattern.inspect}")
    else
      record(desc, true, "#{e.class}: #{e.message}")
    end
  rescue StandardError => e
    record(desc, false, "wrong error: #{e.class}: #{e.message}")
  end

  def record(desc, ok, detail)
    @checks << ok
    status = ok ? 'PASS' : 'FAIL'
    puts format('  [%<status>s] %<desc>s%<extra>s',
                status: status, desc: desc, extra: ok ? '' : " -- #{detail}")
    ok
  end

  def finish!(phase)
    total = @checks.size
    failed = @checks.count { |c| !c }
    puts "\n#{phase}: #{total - failed}/#{total} checks passed"
    exit(failed.zero? ? 0 : 1)
  end
end
