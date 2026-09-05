# Familia security audits

This directory holds the repository's recorded security audits. Each audit
document is the source of truth for its own findings, including their recorded
severity and current resolution status. This page is an index only; it does not
restate finding counts, statuses, or verification results.

## Audit documents

| Document | Scope |
| --- | --- |
| [2026-07-19 audit](2026-07-19-audit.md) | Redacted public summary of the original v2.11.2 audit. Intentionally omits unverified candidates. |
| [2026-07-26 audit](2026-07-26-audit.md) | Commit-ready internal record of the original audit's full finding set, with per-finding status. |
| [2026-07-30 audit](2026-07-30-audit.md) | Delta since 2026-07-19: verification of the earlier fixes and one additional finding. |
| [2026-09-04 audit](2026-09-04-audit.md) | Delta from re-verification of the 2026-07-26 findings: new findings only. |

## How status is recorded

- Each document states the commit at which its findings were last verified and
  records status per finding in place.
- Verification limits (what could and could not be exercised, and in which
  environment) are recorded in the document for that verification, not here.
- A new verification updates the relevant audit document. If it yields new
  findings, they are recorded in a new dated delta document and added to the
  table above.
