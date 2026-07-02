# Encryption Upgrade Proof: AES-256-GCM → XChaCha20-Poly1305

Executable proof that Familia's encryption envelope design permits enabling
XChaCha20-Poly1305 (by installing `rbnacl`/libsodium) while every existing
AES-256-GCM envelope remains decryptable — including envelopes written by
the **released familia 2.10.1 gem**, envelopes written under the pre-#310
static HKDF salt, and envelopes written under a retired master key version.

```
./run.sh
```

## What is being proven

The envelope stored in the database is self-describing JSON:

```json
{
  "algorithm":   "aes-256-gcm | xchacha20poly1305",
  "nonce":       "<base64>",
  "ciphertext":  "<base64>",
  "auth_tag":    "<base64>",
  "key_version": "v1 | v2 | ...",
  "encoding":    "UTF-8",
  "envelope_version": 2,
  "aad_fields":  ["..."]        // v2 envelopes, when aad_fields are used
}
```

Two properties make the upgrade safe:

1. **Write path**: `Registry.default_provider` picks the highest-priority
   *available* provider. Installing rbnacl flips new writes to
   XChaCha20-Poly1305 with zero application changes.
2. **Read path**: `Manager#decrypt` selects the provider from the
   *envelope's* `algorithm` field and derives the key with **that
   provider's** KDF (HKDF-SHA256 for AES-GCM, keyed BLAKE2b for XChaCha),
   using the *envelope's* `key_version` to pick the master key. The default
   provider is never consulted on the read path.

## Phases

Each phase runs in its own process under its own Gemfile; envelopes travel
between phases via `state/*.json`, simulating data at rest in the database.

| Phase | Environment | Simulates |
|---|---|---|
| 0 | familia **2.10.1** (released), OpenSSL only | Production today: all data AES-256-GCM under the static `'FamiliaEncryption'` HKDF salt |
| 1 | this checkout, OpenSSL only | Upgrading the gem before installing libsodium |
| 2 | this checkout + rbnacl | The target state: XChaCha writes, universal reads |
| 3 | this checkout, rbnacl removed | Rollback / mixed-fleet hazard |

Phase 2 additionally proves, by independent recomputation with raw
RbNaCl/OpenSSL primitives (outside familia's code paths):

- the XChaCha data key is literally
  `BLAKE2b(context, key: master_key, personal: personalization)`;
- the AES data key is literally
  `HKDF-SHA256(master_key, salt: hkdf_salt, info: context)`;
- nonces are unique per encryption operation;
- AAD binding, per-record key contexts, auth-tag verification, and
  algorithm-relabeling resistance all hold.

## Hazards the proof documents (deliberately, as passing checks)

These are *current behaviors* pinned by the proof so that any future change
shows up as a failing check. See the accompanying findings report for the
recommendations.

- **Personalization is unrotatable**: changing
  `encryption_personalization` breaks all existing XChaCha ciphertext; there
  is no history/fallback mechanism (unlike `encryption_hkdf_salt_history`).
  Pick the value *before* the first XChaCha write and treat it as permanent.
- **Wiping the current HKDF salt strands current-salt data**: the decrypt
  fallback list rescues legacy-salt envelopes, not envelopes written under
  the salt you just removed.
- **Envelope-lookalike plaintext is stored verbatim**: a plaintext that is
  valid envelope JSON is treated as already-encrypted by the field setter
  and is never encrypted.
- **The upgrade is a one-way door**: once one XChaCha envelope exists,
  every process that may read it needs libsodium. Nodes without it fail
  cleanly (`Familia::EncryptionError: Unsupported algorithm`) but they fail.
  Deploy libsodium to the whole fleet atomically, or accept read errors
  during the rollout window.
