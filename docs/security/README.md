# Familia security audit status

## Current reference

**Last source verification:** 2026-09-04 on `main` at `0633eb41`.

This page is the current, consolidated reference for the repository's recorded
security-audit findings. It combines the status verification in the
[2026-07-26 audit](2026-07-26-audit.md) with the additional findings in the
[2026-09-04 delta audit](2026-09-04-audit.md). The source tree at the current
`HEAD` has no code, test, or workflow changes after that verification; later
changes in this branch are audit documentation only.

This is not a new full security audit. Recorded severities and statuses below
are those of the latest verification, not a reassessment of exploitability or
business impact.

## Summary

Of the 23 findings and candidates in the original audit record, 16 are
resolved, six remain open, and one is partially resolved. The September delta
adds four open findings. In total, the current record contains **10 open
findings and one partially resolved finding**.

| Recorded severity | Finding | Status | Detail |
| --- | --- | --- | --- |
| High | `rebuild_via_scan` lacks normal regression coverage. | Open | [July 26 audit](2026-07-26-audit.md#rebuild-via-scan-coverage) |
| High | A failed SCAN batch can replace a live index with a truncated rebuild. | Open | [July 26 audit](2026-07-26-audit.md#scan-batch-truncated-rebuild) |
| Medium | The Claude workflow action is pinned, but public `@claude` triggers have no evident collaborator or author-association gate. | Partially resolved | [July 26 audit](2026-07-26-audit.md#claude-workflow-public-trigger) |
| Medium | Encrypting before assignment of a record identifier can prevent later decryption. | Open | [July 26 audit](2026-07-26-audit.md#encryption-before-identifier) |
| Medium | Concurrent rebuilds can share a second-resolution temporary key. | Open | [July 26 audit](2026-07-26-audit.md#concurrent-rebuild-temp-key) |
| Medium | `multi_field_fast_write` can break object and external identifier lookups. | Open | [September 4 delta](2026-09-04-audit.md#medium--multi_field_fast_write-can-break-object-and-external-identifier-lookups) |
| Medium | Instance-scoped SCAN rebuild can include records from unrelated scopes. | Open | [September 4 delta](2026-09-04-audit.md#medium--instance-scoped-scan-rebuild-can-populate-an-index-from-unrelated-scopes) |
| Medium | Index rebuild paths retain complete working sets in memory. | Open | [September 4 delta](2026-09-04-audit.md#medium--rebuild-paths-retain-complete-working-sets-in-memory) |
| Low | Variable-length multi-field AAD components can collide after colon joining. | Open | [July 26 audit](2026-07-26-audit.md#multi-field-aad-delimiter-collision) |
| Low | Positional Symbol scopes in verifiable identifiers are silently ignored. | Open | [July 26 audit](2026-07-26-audit.md#positional-symbol-scope) |
| Low | Failed index swaps retain temporary keys indefinitely. | Open | [September 4 delta](2026-09-04-audit.md#low--failed-index-swaps-retain-temporary-keys-indefinitely) |

## Resolved historical audits

- [2026-07-19 public summary](2026-07-19-audit.md): all of its findings are
  resolved. This public document intentionally omits unverified candidates.
- [2026-07-30 historical delta](2026-07-30-audit.md): its claim leak in the
  generated instance-scoped unique-index update method is resolved in
  [PR #372](https://github.com/delano/familia/pull/372). A regression tryout
  verifies that rejected indexing of an unpersisted record leaves no claim.

## Verification limits

The September verification used source inspection and isolated reproductions.
Focused non-database tryouts passed for permission encoding, encryption salt
rotation, encrypted fields, single-use redaction, and verifiable identifiers.
Database-backed indexing tryouts could not run in that environment because the
configured Valkey endpoint at `redis://127.0.0.1:2525` failed socket setup with
`Invalid argument - setsockopt(2)`. The remaining database-backed findings are
therefore source-inspection conclusions, not local integration-test results.
