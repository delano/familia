# examples/encryption_upgrade_proof/phase0_production_today.rb
#
# frozen_string_literal: true

# Phase 0 -- "production today"
#
# Runs against the RELEASED familia 2.10.1 gem (what onetimesecret pins in
# production) with no rbnacl/libsodium. Every envelope written here is
# AES-256-GCM, keyed via HKDF-SHA256 with the static pre-#310 salt
# ('FamiliaEncryption') that 2.10.1 hardcodes. These envelopes are the
# ground-truth fixtures the later phases must keep decrypting.

require_relative 'common'
require_relative 'model'

expected = ENV.fetch('PROOF_EXPECT_VERSION', '2.10.1')
abort "phase0 expects familia #{expected}, got #{Familia::VERSION}" unless Familia::VERSION == expected

Proof.configure!

puts "== Phase 0: production baseline (familia #{Familia::VERSION}, OpenSSL only) =="

Familia::Encryption::Registry.setup!
Proof.check('rbnacl absent: only aes-256-gcm registers') do
  Familia::Encryption::Registry.providers.keys == ['aes-256-gcm']
end
Proof.check('default algorithm is aes-256-gcm') do
  Familia::Encryption.status[:default_algorithm] == 'aes-256-gcm'
end

envelopes = []

# --- Manager-level envelope under the current (v2) master key --------------
ctx = 'ProofApp::Secret:ciphertext:sec_alpha'
pt  = 'the eagle lands at midnight'
env = Familia::Encryption.encrypt(pt, context: ctx, additional_data: ctx)

Proof.check('manager envelope declares aes-256-gcm') { JSON.parse(env)['algorithm'] == 'aes-256-gcm' }
Proof.check('manager envelope records key_version v2') { JSON.parse(env)['key_version'].to_s == 'v2' }
Proof.check('manager envelope roundtrips in-place') do
  Familia::Encryption.decrypt(env, context: ctx, additional_data: ctx) == pt
end
envelopes << { 'label' => 'manager-aes-v2', 'level' => 'manager', 'context' => ctx,
               'aad' => ctx, 'plaintext' => pt, 'envelope' => env }

# --- Manager-level envelope under the OLD (v1) master key ------------------
# Simulates the oldest production data: written when current_key_version was v1.
Proof.configure!(current: :v1)
ctx_v1 = 'ProofApp::Secret:ciphertext:sec_bravo'
pt_v1  = 'older data under the legacy v1 master key'
env_v1 = Familia::Encryption.encrypt(pt_v1, context: ctx_v1, additional_data: ctx_v1)
Proof.configure!(current: :v2)

Proof.check('v1-keyed envelope records key_version v1') { JSON.parse(env_v1)['key_version'].to_s == 'v1' }
Proof.check('v1-keyed envelope decrypts while current version is v2') do
  Familia::Encryption.decrypt(env_v1, context: ctx_v1, additional_data: ctx_v1) == pt_v1
end
envelopes << { 'label' => 'manager-aes-v1', 'level' => 'manager', 'context' => ctx_v1,
               'aad' => ctx_v1, 'plaintext' => pt_v1, 'envelope' => env_v1 }

# --- Field-level envelope through the Horreum encrypted_field path ---------
secret = ProofApp::Secret.new(objid: 'sec_alpha', owner_id: 'cust_1')
secret.ciphertext = 'kept between us'
field_env = secret.ciphertext.encrypted_value

Proof.check('field envelope declares aes-256-gcm') { JSON.parse(field_env)['algorithm'] == 'aes-256-gcm' }
Proof.check('field envelope is a v2 self-describing envelope') { JSON.parse(field_env)['envelope_version'] == 2 }
Proof.check('field value reveals through ConcealedString') do
  secret.ciphertext.reveal { |plain| plain == 'kept between us' }
end
envelopes << { 'label' => 'field-secret-aes', 'level' => 'field', 'model' => 'Secret',
               'objid' => 'sec_alpha', 'owner_id' => 'cust_1',
               'plaintext' => 'kept between us', 'envelope' => field_env }

# --- Field-level envelope with aad_fields -----------------------------------
doc = ProofApp::Document.new(docid: 'doc_1', owner_id: 'cust_9')
doc.content = 'classified paragraph'
doc_env = doc.content.encrypted_value

Proof.check('aad_fields envelope records its aad field list') do
  JSON.parse(doc_env)['aad_fields'] == ['owner_id']
end
envelopes << { 'label' => 'field-document-aes', 'level' => 'field', 'model' => 'Document',
               'docid' => 'doc_1', 'owner_id' => 'cust_9',
               'plaintext' => 'classified paragraph', 'envelope' => doc_env }

Proof.save_state('phase0', 'familia_version' => Familia::VERSION, 'envelopes' => envelopes)
puts "  (#{envelopes.size} fixture envelopes written to state/phase0.json)"

Proof.finish!('Phase 0')
