Security
--------

- Removed the committed HMAC fallback secret in ``Familia::VerifiableIdentifier``
  (issue #310, S1). ``VERIFIABLE_ID_HMAC_SECRET`` is now required; the previous
  default let anyone reading the source forge valid identifiers. The secret is
  resolved lazily on first use (``VerifiableIdentifier.secret_key``), so merely
  requiring the file never raises -- the missing-secret ``KeyError`` surfaces the
  first time an identifier is minted or verified.

- The AES-GCM provider no longer derives keys from a static ``'FamiliaEncryption'``
  HKDF salt (issue #310, S2). It now derives the salt from a dedicated,
  application-specific ``encryption_hkdf_salt`` setting for per-deployment domain
  separation (RFC 5869). Existing ciphertext still decrypts because the legacy
  static salt stays in the decryption fallback list, so **no data migration is
  required**.

- Key derivation now fails closed on a blank salt/personalization (issue #311).
  Encrypting with a nil or empty ``encryption_hkdf_salt`` raises rather than
  silently falling back to the legacy global static salt (which would quietly
  withhold the #310 per-deployment domain separation); decryption stays permissive
  so old ciphertext remains readable. The XChaCha20 providers likewise raise a
  clear error on a nil/empty ``encryption_personalization`` instead of crashing
  with a ``NoMethodError``. The checks live at derivation time, so they also catch
  values set through the raw attribute writer, which bypasses the reader guards.

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

- The AES-GCM HKDF salt is now a dedicated ``encryption_hkdf_salt`` setting,
  separate from ``encryption_personalization`` (issue #311). The personalization
  string feeds only the XChaCha20 providers' BLAKE2b ``personal`` parameter, which
  BLAKE2b caps at 16 bytes; the AES-GCM HKDF salt accepts any length (RFC 5869).
  Decoupling the two inputs means neither cipher family is constrained by the
  other's rules -- in particular, the 16-byte personalization limit no longer
  applies to the AES-GCM salt.

- AES-GCM key derivation supports salt rotation for backward compatibility
  (issues #310 S2, #311). Encryption always uses the current ``encryption_hkdf_salt``;
  decryption tries the current salt, then ``encryption_hkdf_salt_history`` (an
  ordered, current-first config), then the pre-#310 static salt. **No data
  migration is required**: existing ciphertext -- including data written before
  this change -- still decrypts, because the legacy static salt is always in the
  fallback list. When you rotate ``encryption_hkdf_salt``, add the prior value(s)
  to ``encryption_hkdf_salt_history`` so older ciphertext keeps decrypting.

- The opt-in request-scoped key cache now keys on the *resolved* HKDF salt rather
  than the raw argument (issue #311). Previously an encrypt (which lets the
  provider default the salt to ``hkdf_salts.first``) and a later decrypt of the
  same value in one request filed the identical derived key under two different
  cache keys, so the key was derived twice. The cache key is now symmetric across
  encrypt and decrypt, recovering the intended single derivation. Behaviour with
  the cache disabled (the default) is unchanged.

Documentation
-------------

- Clarified that the migration ``Script`` SHA-1 is the Redis ``EVALSHA`` script
  identity (protocol-mandated), not a security checksum (issue #310, S5); genuine
  change-detection already uses SHA-256 in ``Migration::Registry``.
- Documented that ``encryption_personalization`` applies only to the XChaCha20
  (BLAKE2b) providers, and that AES-GCM uses the separate, length-unconstrained
  ``encryption_hkdf_salt`` (issue #311).

AI Assistance
-------------

- These security fixes (issue #310), the AES-GCM salt decoupling and request-cache
  key normalization (issue #311), their failing-first tryouts, the salt-rotation
  backward-compatibility path, and this changelog were drafted with AI assistance.
