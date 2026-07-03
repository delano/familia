# examples/encryption_upgrade_proof/phase2_libsodium_enabled.rb
#
# frozen_string_literal: true

# Phase 2 -- "the upgrade": familia 2.11.x WITH rbnacl/libsodium installed.
#
# This is the target production state. It must hold simultaneously that:
#   1. XChaCha20-Poly1305 becomes the default write algorithm with zero
#      application code changes (provider priority),
#   2. every envelope ever written by AES-256-GCM -- including ones written
#      by the released 2.10.1 gem under the old static HKDF salt, and ones
#      written under the retired v1 master key -- still decrypts, because the
#      envelope is self-describing (algorithm + key_version) and the decrypt
#      path derives keys with the envelope's own provider, not the default,
#   3. the DPA's security claims hold: per-operation random nonces, BLAKE2b
#      key derivation from master secret + class/identifier context, AAD
#      binding that makes ciphertext non-transplantable, and authenticated
#      failure on any tamper.

require_relative 'common'
require_relative 'model'

abort "phase2 expects familia >= 2.11, got #{Familia::VERSION}" if Gem::Version.new(Familia::VERSION) < Gem::Version.new('2.11')
abort 'phase2 expects rbnacl to be loadable' unless defined?(RbNaCl)

Proof.configure!

puts "== Phase 2: familia #{Familia::VERSION} + rbnacl (libsodium #{RbNaCl::Sodium::Version::STRING}) =="

Familia::Encryption::Registry.setup!

# --- 1. Automatic upgrade of the default provider ---------------------------
Proof.check('both providers register') do
  Familia::Encryption::Registry.providers.keys.sort == ['aes-256-gcm', 'xchacha20poly1305']
end
Proof.check('default algorithm flips to xchacha20poly1305 (no app change)') do
  Familia::Encryption.status[:default_algorithm] == 'xchacha20poly1305'
end

# --- 2. Backward compatibility: every prior envelope decrypts ---------------
%w[phase0 phase1].each do |phase|
  state = Proof.load_state(phase)
  from = "#{phase}/familia-#{state['familia_version']}"
  state['envelopes'].each do |rec|
    case rec['level']
    when 'manager'
      Proof.check("#{from} envelope '#{rec['label']}' decrypts with XChaCha default active") do
        Familia::Encryption.decrypt(rec['envelope'], context: rec['context'],
                                                     additional_data: rec['aad']) == rec['plaintext']
      end
    when 'field'
      Proof.check("#{from} envelope '#{rec['label']}' rehydrates + reveals") do
        obj = if rec['model'] == 'Secret'
                ProofApp::Secret.new(objid: rec['objid'], owner_id: rec['owner_id'])
              else
                ProofApp::Document.new(docid: rec['docid'], owner_id: rec['owner_id'])
              end
        field = rec['model'] == 'Secret' ? :ciphertext : :content
        obj.send(:"#{field}=", rec['envelope'])
        obj.send(field).reveal { |plain| plain == rec['plaintext'] }
      end
    end
  end
end

# --- 3. New writes are XChaCha20-Poly1305 ------------------------------------
ctx = 'ProofApp::Secret:ciphertext:sec_delta'
pt  = 'fresh data written after the upgrade'
env = Familia::Encryption.encrypt(pt, context: ctx, additional_data: ctx)
parsed = JSON.parse(env)

Proof.check('new envelope declares xchacha20poly1305') { parsed['algorithm'] == 'xchacha20poly1305' }
Proof.check('new envelope uses a 24-byte (192-bit) nonce') do
  Base64.strict_decode64(parsed['nonce']).bytesize == 24
end
Proof.check('new envelope uses a 16-byte Poly1305 tag') do
  Base64.strict_decode64(parsed['auth_tag']).bytesize == 16
end
Proof.check('new envelope records key_version v2') { parsed['key_version'].to_s == 'v2' }
Proof.check('new envelope roundtrips') do
  Familia::Encryption.decrypt(env, context: ctx, additional_data: ctx) == pt
end

# --- 4. Independent recomputation of the key derivation (DPA claim) ---------
# Prove, without going through familia's decrypt path, that the XChaCha key is
# exactly BLAKE2b(context, key: master_key, personal: personalization): derive
# it by hand with RbNaCl and open the envelope directly with libsodium.
Proof.check('XChaCha key is literally BLAKE2b(master_key, context, personalization)') do
  master  = Base64.strict_decode64(Proof::V2_KEY)
  derived = RbNaCl::Hash.blake2b(ctx.dup.force_encoding('BINARY'),
                                 key: master, digest_size: 32,
                                 personal: Familia.config.encryption_personalization.ljust(16, "\0"))
  box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(derived)
  combined = Base64.strict_decode64(parsed['ciphertext']) + Base64.strict_decode64(parsed['auth_tag'])
  box.decrypt(Base64.strict_decode64(parsed['nonce']), combined, ctx) == pt
end

# The AES path, by contrast, derives with HKDF-SHA256 -- NOT BLAKE2b. Prove it
# the same way for an AES envelope written in phase 1 (salt 'FamilialMatters').
aes_rec = Proof.load_state('phase1')['envelopes'].find { |r| r['label'] == 'manager-aes-211' }
Proof.check('AES-256-GCM key is HKDF-SHA256(master_key, salt, context) -- not BLAKE2b') do
  master  = Base64.strict_decode64(Proof::V2_KEY)
  aes_env = JSON.parse(aes_rec['envelope'])
  derived = OpenSSL::KDF.hkdf(master, salt: 'FamilialMatters', info: aes_rec['context'],
                              length: 32, hash: 'SHA256')
  cipher = OpenSSL::Cipher.new('aes-256-gcm').decrypt
  cipher.key = derived
  cipher.iv = Base64.strict_decode64(aes_env['nonce'])
  cipher.auth_tag = Base64.strict_decode64(aes_env['auth_tag'])
  cipher.auth_data = aes_rec['aad']
  (cipher.update(Base64.strict_decode64(aes_env['ciphertext'])) + cipher.final) == aes_rec['plaintext']
end

# --- 5. Per-operation random nonces ------------------------------------------
Proof.check('500 encryptions of the same value yield 500 distinct nonces and ciphertexts') do
  seen_nonces = {}
  seen_cts = {}
  500.times do
    e = JSON.parse(Familia::Encryption.encrypt(pt, context: ctx, additional_data: ctx))
    seen_nonces[e['nonce']] = true
    seen_cts[e['ciphertext']] = true
  end
  seen_nonces.size == 500 && seen_cts.size == 500
end

# --- 6. Field-level: new writes upgrade, old records re-encrypt --------------
secret = ProofApp::Secret.new(objid: 'sec_delta', owner_id: 'cust_1')
secret.ciphertext = 'field-level secret after upgrade'
field_env = secret.ciphertext.encrypted_value

Proof.check('field envelope declares xchacha20poly1305') do
  JSON.parse(field_env)['algorithm'] == 'xchacha20poly1305'
end
Proof.check('rehydrating an envelope does NOT re-encrypt it (byte-identical passthrough)') do
  again = ProofApp::Secret.new(objid: 'sec_delta', owner_id: 'cust_1')
  again.ciphertext = field_env
  again.ciphertext.encrypted_value == field_env
end

# Take the 2.10.1-written field envelope and upgrade it in place, the way a
# migration (re_encrypt_fields! + save) would.
legacy_rec = Proof.load_state('phase0')['envelopes'].find { |r| r['label'] == 'field-secret-aes' }
migrated = ProofApp::Secret.new(objid: legacy_rec['objid'], owner_id: legacy_rec['owner_id'])
migrated.ciphertext = legacy_rec['envelope']
Proof.check('re_encrypt_fields! upgrades a 2.10.1 AES envelope to XChaCha in place') do
  migrated.re_encrypt_fields!
  upgraded = JSON.parse(migrated.ciphertext.encrypted_value)
  upgraded['algorithm'] == 'xchacha20poly1305' &&
    upgraded['key_version'].to_s == 'v2' &&
    migrated.ciphertext.reveal { |plain| plain == legacy_rec['plaintext'] }
end

# --- 7. Tamper and transplant resistance -------------------------------------
flip = lambda do |b64|
  raw = Base64.strict_decode64(b64)
  raw[0] = (raw[0].ord ^ 0x01).chr
  Base64.strict_encode64(raw)
end

tampered = parsed.merge('ciphertext' => flip.call(parsed['ciphertext']))
Proof.check_raises('flipping one ciphertext bit fails authentication', Familia::EncryptionError) do
  Familia::Encryption.decrypt(JSON.generate(tampered), context: ctx, additional_data: ctx)
end

Proof.check_raises('decrypting with the wrong AAD fails (AAD is authenticated)', Familia::EncryptionError) do
  Familia::Encryption.decrypt(env, context: ctx, additional_data: 'ProofApp::Secret:ciphertext:OTHER')
end

Proof.check_raises('decrypting under another record\'s context fails (per-record keys)',
                   Familia::EncryptionError) do
  other = 'ProofApp::Secret:ciphertext:sec_zulu'
  Familia::Encryption.decrypt(env, context: other, additional_data: other)
end

Proof.check_raises('field-level transplant: envelope moved to another objid fails to reveal',
                   Familia::EncryptionError) do
  thief = ProofApp::Secret.new(objid: 'sec_zulu', owner_id: 'cust_1')
  thief.ciphertext = field_env
  thief.ciphertext.reveal { |plain| plain }
end

Proof.check_raises('sharing a ConcealedString object across records trips context isolation',
                   Familia::EncryptionError, /Context isolation violation/) do
  owner = ProofApp::Secret.new(objid: 'sec_delta', owner_id: 'cust_1')
  owner.ciphertext = field_env
  thief = ProofApp::Secret.new(objid: 'sec_zulu', owner_id: 'cust_1')
  thief.instance_variable_set(:@ciphertext, owner.ciphertext)
  thief.ciphertext
end

# AAD-only mismatch, isolated from key derivation: Document binds owner_id via
# aad_fields; docid (the KDF context) stays identical, only the AAD changes.
doc_rec = Proof.load_state('phase0')['envelopes'].find { |r| r['label'] == 'field-document-aes' }
Proof.check_raises('changing an aad_fields value alone breaks decryption (KDF context unchanged)',
                   Familia::EncryptionError) do
  altered = ProofApp::Document.new(docid: doc_rec['docid'], owner_id: 'cust_ATTACKER')
  altered.content = doc_rec['envelope']
  altered.content.reveal { |plain| plain }
end
Proof.check('...while the correct owner_id still reveals') do
  intact = ProofApp::Document.new(docid: doc_rec['docid'], owner_id: doc_rec['owner_id'])
  intact.content = doc_rec['envelope']
  intact.content.reveal { |plain| plain == doc_rec['plaintext'] }
end

# --- 8. Algorithm-confusion resistance ---------------------------------------
aes_env_parsed = JSON.parse(aes_rec['envelope'])
relabeled = aes_env_parsed.merge('algorithm' => 'xchacha20poly1305')
Proof.check_raises('relabeling an AES envelope as XChaCha fails (nonce size check)',
                   Familia::EncryptionError) do
  Familia::Encryption.decrypt(JSON.generate(relabeled),
                              context: aes_rec['context'], additional_data: aes_rec['aad'])
end

relabeled_back = parsed.merge('algorithm' => 'aes-256-gcm')
Proof.check_raises('relabeling an XChaCha envelope as AES fails (nonce size check)',
                   Familia::EncryptionError) do
  Familia::Encryption.decrypt(JSON.generate(relabeled_back), context: ctx, additional_data: ctx)
end

Proof.check_raises('an unknown algorithm is rejected cleanly', Familia::EncryptionError,
                   /Unsupported algorithm/) do
  Familia::Encryption.decrypt(JSON.generate(parsed.merge('algorithm' => 'rot13')),
                              context: ctx, additional_data: ctx)
end

# --- 9. Config-rotation behaviors (hazards the envelope does NOT cover) ------
# The envelope does not record the BLAKE2b personalization: changing it breaks
# decryption of all existing XChaCha data, and there is no history/fallback
# mechanism (unlike the AES HKDF salt). This documents the hazard.
begin
  Familia.encryption_personalization = 'DifferentApp'
  Proof.check_raises('changing encryption_personalization breaks existing XChaCha data (no fallback!)',
                     Familia::EncryptionError) do
    Familia::Encryption.decrypt(env, context: ctx, additional_data: ctx)
  end
ensure
  Familia.encryption_personalization = 'FamilialMatters'
end
Proof.check('restoring the personalization restores decryption') do
  Familia::Encryption.decrypt(env, context: ctx, additional_data: ctx) == pt
end

# The AES HKDF salt, by contrast, DOES rotate safely via the history list.
begin
  Familia.encryption_hkdf_salt = 'RotatedSalt-2026'
  Familia.encryption_hkdf_salt_history = ['FamilialMatters']
  Proof.check('after salt rotation, envelopes under the previous salt decrypt via history') do
    Familia::Encryption.decrypt(aes_rec['envelope'], context: aes_rec['context'],
                                                     additional_data: aes_rec['aad']) == aes_rec['plaintext']
  end
  legacy_manager = Proof.load_state('phase0')['envelopes'].find { |r| r['label'] == 'manager-aes-v2' }
  Proof.check('...and 2.10.1 envelopes under the pre-#310 static salt decrypt via the built-in fallback') do
    Familia::Encryption.decrypt(legacy_manager['envelope'], context: legacy_manager['context'],
                                                            additional_data: legacy_manager['aad']) == legacy_manager['plaintext']
  end
ensure
  Familia.encryption_hkdf_salt = 'FamilialMatters'
  Familia.encryption_hkdf_salt_history = []
end

# --- 10. Documented edge behaviors -------------------------------------------
Proof.check('encrypting an empty string returns nil (stored as no-value)') do
  Familia::Encryption.encrypt('', context: ctx).nil?
end

# In-band signaling hazard: a PLAINTEXT that happens to look like an envelope
# is treated as already-encrypted by the field setter and stored VERBATIM --
# i.e. never encrypted. See the findings report; this check documents the
# current behavior so any future fix will show up as a diff here.
lookalike = JSON.generate(
  'algorithm' => 'aes-256-gcm',
  'nonce' => Base64.strict_encode64(OpenSSL::Random.random_bytes(12)),
  'ciphertext' => Base64.strict_encode64('attacker controlled bytes'),
  'auth_tag' => Base64.strict_encode64(OpenSSL::Random.random_bytes(16)),
  'key_version' => 'v2'
)
Proof.check('HAZARD (documented): plaintext shaped like an envelope is stored verbatim, unencrypted') do
  s = ProofApp::Secret.new(objid: 'sec_hazard', owner_id: 'cust_1')
  s.ciphertext = lookalike
  s.ciphertext.encrypted_value == lookalike # byte-identical: no encryption happened
end

# --- Persist fixtures for the rollback phase ---------------------------------
Proof.save_state('phase2',
                 'familia_version' => Familia::VERSION,
                 'envelopes' => [
                   { 'label' => 'manager-xchacha', 'level' => 'manager', 'context' => ctx,
                     'aad' => ctx, 'plaintext' => pt, 'envelope' => env },
                   { 'label' => 'field-secret-xchacha', 'level' => 'field', 'model' => 'Secret',
                     'objid' => 'sec_delta', 'owner_id' => 'cust_1',
                     'plaintext' => 'field-level secret after upgrade', 'envelope' => field_env },
                   aes_rec,
                 ])
puts '  (fixtures written to state/phase2.json)'

Proof.finish!('Phase 2')
