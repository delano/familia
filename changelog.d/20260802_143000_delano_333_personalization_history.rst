Added
-----

- New ``encryption_personalization_history`` setting: the BLAKE2b
  personalization used by the XChaCha20-Poly1305 providers can now be rotated,
  mirroring the AES-GCM ``encryption_hkdf_salt_history`` design from 2.11.0
  (#311). Encryption always uses the current ``encryption_personalization``;
  decryption tries the current value first, then each history entry in order,
  then the pre-rotation built-in default (``'FamilialMatters'``), so existing
  ciphertext keeps decrypting across rotations and upgrades. Candidates that
  violate BLAKE2b's constraints (non-String, blank, null bytes, over 16 bytes)
  are skipped rather than aborting the walk. The rotation logic lives in a new
  shared ``Familia::Encryption::Providers::Blake2bPersonalization`` module
  included by both XChaCha20 providers, so the registered provider and its
  unregistered ``Secure`` sibling can no longer drift apart (as they did in
  #250 and #356). The default personalization is unchanged, so unrotated
  deployments encrypt and decrypt exactly as under 2.11. #333

Changed
-------

- ``Manager#decrypt`` walks the XChaCha20 providers' personalization
  candidates exactly as it walks AES-GCM's HKDF salts; each provider exposes
  at most one rotation dimension, never both. A candidate that fails while
  deriving now falls through to the next candidate instead of aborting the
  walk, and an explicit over-long ``personal:`` passed to ``derive_key``
  raises ``Familia::EncryptionError`` instead of leaking
  ``RbNaCl::LengthError``. #333

- The opt-in request-scoped key cache key gained a personalization segment
  (``algorithm:version:salt:personal:context``), so derivations under
  different rotation candidates never collide while an encrypt and a later
  decrypt of the same value within one request still share a single derived
  key. #333

Documentation
-------------

- The encryption upgrade proof (``examples/encryption_upgrade_proof/``) no
  longer pins "personalization is unrotatable" as a hazard: phase 2 now
  proves that after rotating ``encryption_personalization``, envelopes
  written under the built-in default keep decrypting via the legacy fallback
  and via an explicit history entry. The encrypted-fields and encryption
  guides, the overview, and the technical reference document
  ``encryption_personalization_history`` alongside the salt history,
  including a rotation example. #333

AI Assistance
-------------

- The shared ``Blake2bPersonalization`` module, the manager decrypt-walk and
  cache-key changes, the upgrade-proof and guide updates, and this changelog
  entry were drafted with AI assistance. #333
