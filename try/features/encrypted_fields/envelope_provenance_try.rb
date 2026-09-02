# try/features/encrypted_fields/envelope_provenance_try.rb
#
# frozen_string_literal: true
#
# Envelope provenance (issue #405).
#
# The encrypted field setter used to decide "this is already an envelope, keep
# it verbatim" by duck-typing the assigned value: any JSON carrying the five
# envelope keys skipped encryption. A caller who assigned plaintext shaped like
# an envelope therefore had that plaintext stored unencrypted, under a field the
# library documents as encrypted at rest.
#
# Now only a value the hydration path has wrapped in
# Familia::Encryption::StoredEnvelope (via EncryptedFieldType#deserialize, called
# from Horreum's storage-to-object path) is taken verbatim. Everything assigned
# by application code -- the setter, the fast writer, apply_fields, keyword
# construction -- is plaintext and gets encrypted, whatever it looks like.
# (multi_field_update already refuses raw values for encrypted fields.)

require_relative '../../support/helpers/test_helpers'
require 'base64'

set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) },
                         current_version: :v1)
Familia::Encryption::Registry.setup!

class EnvelopeProvenanceModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

# A structurally valid envelope: real algorithm, correctly sized nonce and
# auth_tag, existing key_version. Exactly what an attacker can construct from
# public information, and exactly what passed the old shape check.
@donor = EnvelopeProvenanceModel.new(id: 'prov-donor')
@donor.secret = 'donor-plaintext'
@donor.save
@lookalike = @donor.secret.encrypted_value
@lookalike_ciphertext = Familia::JsonSerializer.parse(@lookalike)['ciphertext']

def ciphertext_of(envelope_json)
  Familia::JsonSerializer.parse(envelope_json)['ciphertext']
end

## The lookalike still passes the shape check (it IS a well-formed envelope)
EnvelopeProvenanceModel.field_types[:secret].encrypted_json?(@lookalike)
#=> true

## Assigning an envelope-shaped string through the setter encrypts it as plaintext
@target = EnvelopeProvenanceModel.new(id: 'prov-target')
@target.secret = @lookalike
ciphertext_of(@target.secret.encrypted_value) != @lookalike_ciphertext
#=> true

## Revealing gives back the assigned string itself, not the donor's plaintext
@target.secret.reveal { |plain| plain }
#=> @lookalike

## What lands at rest is a fresh envelope, not the caller's bytes
@target.save
@stored_target = @target.dbclient.hget(@target.dbkey, 'secret')
[@stored_target == @lookalike, ciphertext_of(@stored_target) != @lookalike_ciphertext]
#=> [false, true]

## Round-tripping the encrypted lookalike through storage still reveals it
EnvelopeProvenanceModel.find_by_id('prov-target').secret.reveal { |plain| plain }
#=> @lookalike

## An envelope-shaped Hash is plaintext too
@hash_target = EnvelopeProvenanceModel.new(id: 'prov-hash')
@hash_target.secret = Familia::JsonSerializer.parse(@lookalike)
[@hash_target.secret.class, ciphertext_of(@hash_target.secret.encrypted_value) != @lookalike_ciphertext]
#=> [ConcealedString, true]

## Keyword-argument construction is a caller assignment, so it encrypts
@kw = EnvelopeProvenanceModel.new(id: 'prov-kw', secret: @lookalike)
ciphertext_of(@kw.secret.encrypted_value) != @lookalike_ciphertext
#=> true

## multi_field_update already refuses raw values for encrypted fields, lookalike or not
@mfu = EnvelopeProvenanceModel.new(id: 'prov-mfu')
@mfu.save
@mfu.multi_field_update(secret: @lookalike)
#=!> ArgumentError
#==> error.message.include?('cannot be written from a String')

## multi_field_update left nothing at rest for the refused value
@mfu.dbclient.hexists(@mfu.dbkey, 'secret')
#=> false

## The fast writer encrypts an envelope-shaped value before persisting it
@fast = EnvelopeProvenanceModel.new(id: 'prov-fast')
@fast.save
@fast.secret!(@lookalike)
@stored_fast = @fast.dbclient.hget(@fast.dbkey, 'secret')
[@stored_fast == @lookalike, ciphertext_of(@stored_fast) != @lookalike_ciphertext]
#=> [false, true]

## Hydration keeps the stored envelope verbatim (no re-encryption on load)
@reloaded = EnvelopeProvenanceModel.find_by_id('prov-donor')
@reloaded.secret.encrypted_value == @donor.dbclient.hget(@donor.dbkey, 'secret')
#=> true

## The reloaded value decrypts to the original plaintext
@reloaded.secret.reveal { |plain| plain }
#=> 'donor-plaintext'

## refresh! goes through the same hydration path
@fresh = EnvelopeProvenanceModel.new(id: 'prov-donor')
@fresh.refresh!
[@fresh.secret.encrypted_value == @lookalike, @fresh.secret.reveal { |plain| plain }]
#=> [true, 'donor-plaintext']

## The storage hook wraps decoded values in StoredEnvelope
@hook = EnvelopeProvenanceModel.field_types[:secret].deserialize(Familia::JsonSerializer.parse(@lookalike))
[@hook.class, @hook.payload.class]
#=> [Familia::Encryption::StoredEnvelope, Hash]

## The storage hook passes nil through unchanged
EnvelopeProvenanceModel.field_types[:secret].deserialize(nil)
#=> nil

## A StoredEnvelope assigned directly is honoured -- it is the marker, not the shape
@marked = EnvelopeProvenanceModel.new(id: 'prov-donor')
@marked.secret = Familia::Encryption::StoredEnvelope.new(payload: @lookalike)
[@marked.secret.encrypted_value == @lookalike, @marked.secret.reveal { |plain| plain }]
#=> [true, 'donor-plaintext']

## Legacy plaintext at rest is encrypted in memory on hydration and still reveals
# (refresh! rather than find_by_id: loading any record whose hash holds a
# non-JSON legacy string through find_by_id trips a pre-existing NoIdentifier
# in the deserialization logger, unrelated to encrypted fields.)
@legacy_key = EnvelopeProvenanceModel.dbkey('prov-legacy')
EnvelopeProvenanceModel.dbclient.hset(@legacy_key, 'id', '"prov-legacy"')
EnvelopeProvenanceModel.dbclient.hset(@legacy_key, 'secret', 'plain-at-rest')
@legacy = EnvelopeProvenanceModel.new(id: 'prov-legacy')
@legacy.refresh!
[EnvelopeProvenanceModel.field_types[:secret].encrypted_json?(@legacy.secret.encrypted_value),
 @legacy.secret.reveal { |plain| plain }]
#=> [true, 'plain-at-rest']

# TEARDOWN
%w[prov-donor prov-target prov-hash prov-kw prov-mfu prov-fast prov-legacy].each do |id|
  EnvelopeProvenanceModel.dbclient.del(EnvelopeProvenanceModel.dbkey(id))
end
if EnvelopeProvenanceModel.respond_to?(:instances)
  EnvelopeProvenanceModel.dbclient.del(EnvelopeProvenanceModel.instances.dbkey)
end
clear_test_encryption_keys
