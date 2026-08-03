Security
--------

- The encrypt-path request-cache key now resolves the HKDF salt through the
  fail-closed ``current_hkdf_salt`` accessor instead of the permissive
  candidate list's head (``hkdf_salts.first``). Previously, with a blank
  ``encryption_hkdf_salt``, a decrypt inside ``with_request_cache`` could
  warm an entry keyed on a historical salt that a subsequent encrypt would
  silently reuse -- because the cache lookup precedes derivation, the
  blank-salt refusal in the provider never fired. Encrypts now refuse a
  blank salt even against a warm cache. #380

Changed
-------

- With a blank ``encryption_hkdf_salt``, ``Manager#encrypt`` now raises
  ``EncryptionError`` when the request-cache key is built rather than at key
  derivation. The raise happens earlier and now also fires on what would
  previously have been a warm-cache hit; correctly configured deployments see
  no change. #380

AI Assistance
-------------

- Claude Code implemented the fail-closed cache-key resolution, added a
  warm-cache regression tryout, and verified the encryption tryout files
  pass (and that the new case fails without the fix).
