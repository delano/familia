Fixed
-----

- ``SecureXChaCha20Poly1305Provider#derive_key`` no longer mutates the context
  string it is given. It passed ``context.force_encoding('BINARY')`` to
  BLAKE2b, and ``force_encoding`` mutates its receiver: the caller's string
  came back re-tagged as ``ASCII-8BIT``, and a frozen context (routine under
  ``# frozen_string_literal: true``) raised ``FrozenError`` instead of
  deriving a key. The provider now hashes a fresh binary copy via
  ``context.to_s.b``, matching the fix made to the sibling
  ``XChaCha20Poly1305Provider`` in #250 -- which also means a ``Symbol`` or
  ``nil`` context no longer raises ``NoMethodError``. Derived keys are
  byte-for-byte unchanged (only the encoding tag differed, never the bytes
  hashed), so no stored ciphertext needs re-encryption. Found by the
  2026-07-19 security audit. #356

AI Assistance
-------------

- AI reproduced both symptoms (caller-string encoding flip and ``FrozenError``
  on a frozen context) against the unfixed provider, applied the ``to_s.b``
  fix, and added regression coverage asserting that the caller's encoding is
  preserved, that a frozen context derives successfully, that non-String
  contexts are tolerated, and that the derived key still matches the sibling
  provider byte for byte.
