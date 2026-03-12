.. A new scriv changelog fragment.

Added
-----

- Encrypt now records the original plaintext encoding in the EncryptedData
  envelope (``encoding`` field), completing the Phase 2 encoding round-trip
  fix. Decrypt (Phase 1, #228) already falls back to UTF-8 when the field
  is absent, so this change is backward-compatible. PR #229

AI Assistance
-------------

- Implementation and test authoring delegated to backend-dev agents, with
  orchestration and Phase 1 test fixups handled in the main session. Claude
  Opus 4.6.
