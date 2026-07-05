Added
-----

- ``encrypted_field`` now honors a per-field ``algorithm:`` option, pinning that
  field's write algorithm to a specific registered provider (``'aes-256-gcm'`` or
  ``'xchacha20poly1305'``) independent of the registry's default-provider
  priority. The option was previously documented but silently ignored, so writes
  always used the default provider. Decryption stays envelope-driven, so a pin can
  be added, changed, or removed without breaking ciphertext already at rest, and
  ``re_encrypt_fields!`` re-encrypts under the pin rather than the default. This is
  the supported lever for a reader-before-writer format migration: deploy
  ``rbnacl`` fleet-wide so every node can *read* XChaCha20-Poly1305 while keeping
  *writes* pinned to AES-256-GCM until all readers are confirmed capable, then drop
  the pin. Issue #334

Documentation
-------------

- The encrypted-fields guide previously showed a ``provider: :aes_gcm`` field
  option that was never implemented; those examples now use the real
  ``algorithm: 'aes-256-gcm'`` form, and the ``Familia::Encryption`` facade
  docstring documents the shipped behavior instead of a hypothetical
  implementation sketch. Issue #334

AI Assistance
-------------

- The per-field algorithm implementation, its regression tryouts, the guide
  corrections, and this changelog entry were drafted with AI assistance. Issue #334
