Security
--------

- ``Familia::VerifiableIdentifier`` now requires ``VERIFIABLE_ID_HMAC_SECRET``
  (issue #310, S1). The committed fallback secret, which allowed identifier
  forgery, is removed; the secret is read lazily, so requiring the file without it
  set does not raise.

- AES-GCM keys derive from a per-deployment ``encryption_hkdf_salt`` instead of a
  static library salt (issue #310, S2). A blank salt or personalization now raises
  rather than silently using a weak/global value; existing ciphertext still
  decrypts (issue #311).

- External identifiers derive via SHA-256, or keyed HMAC-SHA256 with a ``secret:``,
  instead of a Mersenne-Twister PRNG seeded from a truncated digest (issue #310, S3).

- ``ParticipationMembership#target_instance`` resolves class names through the
  ``Familia.resolve_class`` allowlist instead of ``Object.const_get`` (issue #310, S4).

- The request-scoped key cache is wiped on entry to ``with_request_cache`` as well
  as on exit, so a reused fiber cannot inherit another request's keys (issue #310, S6).

Changed
-------

- New ``encryption_hkdf_salt`` and ``encryption_hkdf_salt_history`` settings
  configure the AES-GCM HKDF salt, decoupled from ``encryption_personalization``
  (now used only by the XChaCha20/BLAKE2b providers, still capped at 16 bytes). The
  salt has no length limit and supports rotation; no data migration is required
  (issue #311).

- ``feature :external_identifier`` accepts a callable ``secret:``, resolved lazily
  at first use (issue #311).

- The opt-in request-scoped key cache keys on the resolved salt, so an encrypt and a
  later decrypt of the same value within one request share a single derived key
  (issue #311).

Documentation
-------------

- Clarified that the migration ``Script`` SHA-1 is the Redis ``EVALSHA`` identity,
  not a security checksum (issue #310, S5).

AI Assistance
-------------

- These changes (issues #310 and #311), their tryouts, and this changelog were
  drafted with AI assistance.
