# examples/encryption_upgrade_proof/phase3_rollback_hazard.rb
#
# frozen_string_literal: true

# Phase 3 -- "the one-way door": remove rbnacl again after XChaCha data exists.
#
# This phase demonstrates the operational hazard of the upgrade: once any
# envelope has been written as xchacha20poly1305, every node that can be asked
# to decrypt it MUST have rbnacl/libsodium. A node without it fails cleanly
# (Familia::EncryptionError, no garbage plaintext) -- but it fails. The same
# applies to a mixed fleet mid-rolling-deploy: an upgraded node writes
# XChaCha, a not-yet-upgraded node cannot read it.
#
# AES envelopes remain readable throughout, so rollback only strands data
# written after the upgrade.

require_relative 'common'
require_relative 'model'

abort "phase3 expects familia >= 2.11, got #{Familia::VERSION}" if Familia::VERSION < '2.11'
abort 'phase3 expects rbnacl to be ABSENT' if defined?(RbNaCl)

Proof.configure!

puts "== Phase 3: rollback / mixed-fleet hazard (familia #{Familia::VERSION}, rbnacl removed) =="

Familia::Encryption::Registry.setup!
Proof.check('only aes-256-gcm registers again') do
  Familia::Encryption::Registry.providers.keys == ['aes-256-gcm']
end

phase2 = Proof.load_state('phase2')
xchacha_manager = phase2['envelopes'].find { |r| r['label'] == 'manager-xchacha' }
xchacha_field   = phase2['envelopes'].find { |r| r['label'] == 'field-secret-xchacha' }
aes_rec         = phase2['envelopes'].find { |r| r['label'] == 'manager-aes-211' }

Proof.check_raises('XChaCha envelope fails CLEANLY without rbnacl (no silent garbage)',
                   Familia::EncryptionError, /Unsupported algorithm/) do
  Familia::Encryption.decrypt(xchacha_manager['envelope'],
                              context: xchacha_manager['context'],
                              additional_data: xchacha_manager['aad'])
end

Proof.check_raises('field-level rehydration of an XChaCha envelope fails loudly at wrap time',
                   Familia::EncryptionError, /Unsupported algorithm/) do
  s = ProofApp::Secret.new(objid: xchacha_field['objid'], owner_id: xchacha_field['owner_id'])
  s.ciphertext = xchacha_field['envelope']
  s.ciphertext.reveal { |plain| plain }
end

Proof.check('AES envelopes written before and during the upgrade still decrypt') do
  Familia::Encryption.decrypt(aes_rec['envelope'], context: aes_rec['context'],
                                                   additional_data: aes_rec['aad']) == aes_rec['plaintext']
end

Proof.finish!('Phase 3')
