Fixed
-----

- ``Horreum#destroy!`` now cleans up class-level ``unique_index`` and
  ``multi_index`` entries within the same transaction that deletes the
  object hash and removes it from the ``instances`` timeline. Previously,
  stale entries remained and caused ``RecordExistsError`` on a subsequent
  ``create!`` with the same indexed value. Issue #241.

- Aligned ``guard_unique_indexes!`` with the ``within`` filter used by
  ``auto_update_class_indexes`` and the new ``remove_from_class_indexes!``
  helper, keeping validate/update/cleanup paths symmetric for any future
  ``unique_index`` declared ``within: :class``.

Changed
-------

- Instance-scoped index entries (``unique_index`` / ``multi_index``
  declared with ``within: SomeClass``) remain orphaned after ``destroy!``.
  This is a known limitation carried over from prior releases and now
  tracked separately as issue #244. Until that issue is closed, callers
  using instance-scoped indexes should remove entries explicitly (e.g.,
  ``employee.remove_from_company_badge_index(company)``) before
  ``destroy!``.

AI Assistance
-------------

- Issue triage, code review, failing-tryout authoring, and implementation
  were coordinated across several specialized Claude Code agents
  (qa-automation-engineer for test coverage, backend-dev for the fix,
  feature-dev:code-reviewer for verification of transaction atomicity
  and filter symmetry).
