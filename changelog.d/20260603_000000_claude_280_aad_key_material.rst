Added
-----

- ``encrypted_field`` now accepts a ``key_material:`` option: a proc returning
  additional entropy that is mixed into key derivation (BLAKE2b context),
  separate from ``aad_fields``. Unlike AAD (which binds via the authentication
  tag, so a wrong value fails with an auth mismatch), wrong ``key_material``
  derives a different key entirely and produces garbage output. Use it to bind
  ciphertext to a value the holder must supply at decrypt time, e.g.
  ``key_material: ->(rec) { rec.passphrase }``. The proc may return a
  ``RedactedString`` (its real value is extracted via ``.value``). When used,
  the envelope records ``key_material_fields`` so decryption knows to re-apply
  the proc. PR #280

- Encrypted-field envelopes now carry an internal ``envelope_version`` (``2``)
  plus the ``aad_fields`` used at encrypt time. Decryption rebuilds AAD from the
  envelope's own field list rather than the current class declaration, so
  changing a model's ``aad_fields`` no longer breaks previously-encrypted values.
  Envelopes without a version fall back to the legacy class-level path. PR #280

Fixed
-----

- ``aad_fields`` containing a ``transient_field`` now bind to the field's real
  value. Previously ``build_aad`` called ``RedactedString#to_s``, which returns
  ``"[REDACTED]"`` for every value -- so all passphrases produced identical AAD
  and the binding was defeated. AAD now extracts the underlying value via
  ``RedactedString#value``. PR #280

Security
--------

- The ``aad_fields`` transient-field fix changes AAD output for any field that
  lists a ``transient_field``. Values encrypted by an earlier release using a
  transient field in ``aad_fields`` were bound to ``"[REDACTED]"`` and will no
  longer decrypt after upgrading (they had no real binding to begin with). This
  affects transient ``aad_fields`` only; regular fields are unchanged. Re-encrypt
  affected values if any exist. PR #280

AI Assistance
-------------

- AI reviewed the initial #280 implementation, identifying that envelope
  serialization was hand-rolled in ``EncryptedFieldType`` while the
  ``EncryptedData`` value object was extended but bypassed. Refactored so
  envelope construction/parsing flows through ``EncryptedData`` (``with_metadata``,
  ``to_json``, ``has_key_material?``, ``stored_aad_fields``), collapsed duplicate
  AAD builders into one ``build_aad(record, fields:)``, extracted shared
  ``RedactedString`` unwrapping and context-entropy helpers, and made
  ``envelope_version`` load-bearing by branching the decrypt path on it. Added
  test coverage for the value-object round-trips and version branching, including
  the backward-incompatible transient-AAD edge case.
