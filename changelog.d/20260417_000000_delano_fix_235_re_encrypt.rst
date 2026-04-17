Fixed
-----

- **Encryption**: Fixed ``re_encrypt_fields!`` silently failing to re-encrypt fields under the current key version. Previously the method passed the existing ``ConcealedString`` back through the setter, which the setter preserves as-is for rehydration purposes, so no re-encryption occurred and the stored ciphertext retained its original ``key_version``. The method now reveals plaintext via ``ConcealedString#reveal`` and re-assigns it, forcing encryption under the current key version and algorithm. Issue #235

Security
--------

- **Encryption**: Key rotation via ``re_encrypt_fields!`` was a silent no-op for fields already loaded as ``ConcealedString`` (the normal case for objects rehydrated from Redis). Callers who followed the documented rotation workflow -- load, ``re_encrypt_fields!``, ``save`` -- left data encrypted under old, potentially compromised keys while believing rotation had succeeded. The stored ciphertext's ``key_version`` remained unchanged. Issue #235

Documentation
-------------

- Clarified in both ``docs/guides/encryption.md`` and ``docs/guides/feature-encrypted-fields.md`` that ``re_encrypt_fields!`` mutates in-memory state only and requires an explicit ``save`` to persist. Reworked the key rotation example in ``examples/encrypted_fields.rb`` to demonstrate the real rotation flow (save under v1, add v2, load fresh, re-encrypt, save) rather than pre-assigning plaintext (which masked the bug). Issue #235

AI Assistance
-------------

- Collaborated with Claude on isolating the no-op root cause (the setter's ConcealedString-preservation branch), drafting the raw-envelope regression canary that inspects ``key_version`` in stored JSON, reworking ``examples/encrypted_fields.rb`` to exercise the real rotation flow rather than pre-assigning plaintext, and adding edge-case coverage for nonce freshness, missing-old-key failures, type-guard assertions, and mixed encrypted/plain/transient field models. Issue #235
