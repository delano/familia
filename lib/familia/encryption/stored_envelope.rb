# lib/familia/encryption/stored_envelope.rb
#
# frozen_string_literal: true

module Familia
  module Encryption
    # Provenance marker for an encrypted field's value as read back from storage.
    #
    # An encrypted field's setter has to decide whether the value it was handed
    # is plaintext to encrypt or an envelope to keep verbatim. Deciding that by
    # shape -- does it parse as JSON carrying the envelope keys? -- let a caller
    # land plaintext at rest unencrypted simply by making it look like an
    # envelope (#405). So the setter no longer infers provenance from shape.
    # Only a value wrapped in this class takes the verbatim path, and only the
    # hydration hook (EncryptedFieldType#deserialize, reached from load,
    # find_by_id, refresh! and the other storage-to-object paths) wraps. Every
    # other assignment -- the plain setter, the fast writer, apply_fields,
    # keyword-argument construction -- is plaintext and gets encrypted, whatever
    # it looks like. (multi_field_update and multi_field_fast_write already
    # refuse anything but a ConcealedString for an encrypted field.)
    #
    # The payload is whatever deserialize_value produced for the stored field:
    # normally the parsed envelope (a Hash), occasionally a String when a legacy
    # plaintext value sits in the slot. EncryptedFieldType decides what to do
    # with each; this class only records where the value came from.
    StoredEnvelope = Data.define(:payload)
  end
end
