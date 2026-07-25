# ADR-0001: Record architecture decisions

**Status:** accepted · 2026-07-25

## Context

Familia's concurrency and persistence semantics are subtle (transaction modes,
WATCH choreography, index guards). The reasoning behind them lives in PR
threads and commit messages, where it gets relitigated or silently violated.

## Decision

Keep terse ADRs in `docs/adr/`, one per decision, per the format in README.md.
New code that touches a decided area follows the ADR or supersedes it
explicitly.

## Consequences

Decisions are findable and citeable in review. The index in README.md must be
updated with each ADR.
