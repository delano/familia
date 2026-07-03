# examples/encryption_upgrade_proof/phase1_gem_upgrade_no_libsodium.rb
#
# frozen_string_literal: true

# Phase 1 -- "upgrade the familia gem, nothing else"
#
# Runs against the local familia checkout (2.11.x) WITHOUT rbnacl. This is
# the intermediate deployment state: the library upgraded, libsodium still
# absent. Everything must keep working exactly as before, and every envelope
# written by the released 2.10.1 gem (phase 0) must still decrypt -- across
# the HKDF salt change between the two versions (2.10.1 hardcoded
# 'FamiliaEncryption'; 2.11.x defaults to 'FamilialMatters' and keeps the old
# value as a decrypt-time fallback).

require_relative 'common'
require_relative 'model'

abort "phase1 expects familia >= 2.11, got #{Familia::VERSION}" if Gem::Version.new(Familia::VERSION) < Gem::Version.new('2.11')

Proof.configure!

puts "== Phase 1: gem upgraded to #{Familia::VERSION}, still no rbnacl =="

Familia::Encryption::Registry.setup!
Proof.check('rbnacl absent: only aes-256-gcm registers') do
  Familia::Encryption::Registry.providers.keys == ['aes-256-gcm']
end
Proof.check('default algorithm remains aes-256-gcm') do
  Familia::Encryption.status[:default_algorithm] == 'aes-256-gcm'
end
Proof.check('current HKDF salt differs from the salt 2.10.1 encrypted under') do
  Familia.config.encryption_hkdf_salt == 'FamilialMatters'
end

# --- Every 2.10.1 envelope must still decrypt -------------------------------
phase0 = Proof.load_state('phase0')
phase0['envelopes'].each do |rec|
  case rec['level']
  when 'manager'
    Proof.check("2.10.1 envelope '#{rec['label']}' decrypts after gem upgrade (salt fallback)") do
      Familia::Encryption.decrypt(rec['envelope'], context: rec['context'],
                                                   additional_data: rec['aad']) == rec['plaintext']
    end
  when 'field'
    Proof.check("2.10.1 envelope '#{rec['label']}' rehydrates + reveals after gem upgrade") do
      obj = if rec['model'] == 'Secret'
              ProofApp::Secret.new(objid: rec['objid'], owner_id: rec['owner_id'])
            else
              ProofApp::Document.new(docid: rec['docid'], owner_id: rec['owner_id'])
            end
      field = rec['model'] == 'Secret' ? :ciphertext : :content
      obj.send(:"#{field}=", rec['envelope']) # setter recognizes envelope JSON: rehydration, no re-encrypt
      obj.send(field).reveal { |plain| plain == rec['plaintext'] }
    end
  end
end

# --- New writes still work and are still AES --------------------------------
envelopes = []
ctx = 'ProofApp::Secret:ciphertext:sec_charlie'
pt  = 'written by 2.11 before libsodium arrives'
env = Familia::Encryption.encrypt(pt, context: ctx, additional_data: ctx)
Proof.check('new envelope still declares aes-256-gcm') { JSON.parse(env)['algorithm'] == 'aes-256-gcm' }
Proof.check('new envelope roundtrips') do
  Familia::Encryption.decrypt(env, context: ctx, additional_data: ctx) == pt
end
envelopes << { 'label' => 'manager-aes-211', 'level' => 'manager', 'context' => ctx,
               'aad' => ctx, 'plaintext' => pt, 'envelope' => env }

# --- The #311 fail-closed guard on a broken salt config ---------------------
begin
  Familia.encryption_hkdf_salt = nil # attr_writer bypasses the reader's guards
  Proof.check_raises('encrypting with a nil HKDF salt fails closed (issue #311 guard)',
                     Familia::EncryptionError, /encryption_hkdf_salt/) do
    Familia::Encryption.encrypt('x', context: ctx, additional_data: ctx)
  end
  # The decrypt fallback list drops the blank current salt and keeps the
  # legacy entries, so LEGACY-salt ciphertext survives a broken config...
  legacy = phase0['envelopes'].find { |r| r['label'] == 'manager-aes-v2' }
  Proof.check('legacy-salt ciphertext still decrypts with a nil current salt (fallback list)') do
    Familia::Encryption.decrypt(legacy['envelope'], context: legacy['context'],
                                                    additional_data: legacy['aad']) == legacy['plaintext']
  end
  # ...but ciphertext written under the wiped CURRENT salt does not: the nil
  # salt is compacted away, so its derivation input is simply gone. The
  # comment on AESGCMProvider#hkdf_salts ("existing ciphertext stays readable
  # even if the current config is broken") only holds for legacy-salt data.
  Proof.check_raises('current-salt ciphertext does NOT survive wiping the current salt (documented gap)',
                     Familia::EncryptionError) do
    Familia::Encryption.decrypt(env, context: ctx, additional_data: ctx)
  end
ensure
  Familia.encryption_hkdf_salt = 'FamilialMatters'
end

Proof.save_state('phase1', 'familia_version' => Familia::VERSION, 'envelopes' => envelopes)
puts "  (#{envelopes.size} fixture envelopes written to state/phase1.json)"

Proof.finish!('Phase 1')
