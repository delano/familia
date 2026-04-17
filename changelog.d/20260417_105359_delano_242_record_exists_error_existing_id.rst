Changed
-------

- ``Familia::RecordExistsError`` now exposes ``#existing_id`` and appends
  ``(existing_id=<id>)`` to its message when raised by the unique-index
  guards in ``guard_unique_indexes!``. Diagnosing stale-index drift no
  longer requires a secondary ``HGET`` to compare the drifted identifier
  against the one on the record being saved. The attribute defaults to
  ``nil`` and the message format is unchanged when absent, so existing
  rescue patterns and the primary-key collision raised by
  ``save_if_not_exists!`` are untouched. Issue #242.

AI Assistance
-------------

- Implementation and test coverage drafted with Claude Code
  (backend-dev + qa-automation-engineer subagents), reviewed by
  feature-dev:code-reviewer.
