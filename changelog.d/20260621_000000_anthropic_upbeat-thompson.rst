Security
--------

- Removed the committed HMAC fallback secret in ``Familia::VerifiableIdentifier``
  (issue #310, S1). ``VERIFIABLE_ID_HMAC_SECRET`` is now required; the previous
  default let anyone reading the source forge valid identifiers. The secret is
  resolved lazily on first use (``VerifiableIdentifier.secret_key``), so merely
  requiring the file never raises -- the missing-secret ``KeyError`` surfaces the
  first time an identifier is minted or verified.

- The AES-GCM provider no longer derives keys from a static ``'FamiliaEncryption'``
  HKDF salt (issue #310, S2). It now uses the application
  ``encryption_personalization`` for per-deployment domain separation, mirroring
  the XChaCha20 providers.

- External identifiers are no longer derived with Ruby's ``Random`` (Mersenne
  Twister) seeded from a 64-bit-truncated digest (issue #310, S3). Derivation is
  now a deterministic SHA-256 over the full objid, or a keyed HMAC-SHA256 when a
  ``secret:`` option is configured on ``feature :external_identifier``.

- ``ParticipationMembership#target_instance`` resolves the database-sourced class
  name through ``Familia.resolve_class`` (model-registry allowlist) instead of
  ``Object.const_get`` (issue #310, S4), so a writable database cannot coerce
  resolution of an arbitrary constant.

- The request-scoped key cache is now wiped on entry to ``with_request_cache`` as
  well as on exit (issue #310, S6), so a reused fiber never begins a block
  carrying a previous request's derived keys.

Changed
-------

- AES-GCM key derivation supports salt rotation for backward compatibility
  (issue #310, S2). Encryption always uses the current ``encryption_personalization``;
  decryption tries the current salt, then ``encryption_personalization_history``
  (a new, ordered, current-first config), then the pre-#310 static salt. **No
  data migration is required**: existing ciphertext -- including data written
  before this change -- still decrypts, because the legacy static salt is always
  in the fallback list. When you rotate ``encryption_personalization``, add the
  prior value(s) to ``encryption_personalization_history`` so older ciphertext
  keeps decrypting.

Documentation
-------------

- Clarified that the migration ``Script`` SHA-1 is the Redis ``EVALSHA`` script
  identity (protocol-mandated), not a security checksum (issue #310, S5); genuine
  change-detection already uses SHA-256 in ``Migration::Registry``.
- Corrected docs that described ``encryption_personalization`` as "XChaCha20 only";
  it now also seeds the AES-GCM HKDF salt.

AI Assistance
-------------

- These security fixes (issue #310), their failing-first tryouts, the salt-rotation
  backward-compatibility path, and this changelog were drafted with AI assistance.
