Added
-----

- Orphaned related-field detection for Horreum models.
  ``audit_related_fields`` SCANs for instance-level collection keys
  (``list``, ``set``, ``zset``, ``hashkey``) whose parent hash no
  longer exists and reports them per field with
  ``{field_name:, klass:, orphaned_keys:, count:, status:}``. Orphans
  can accumulate when ``destroy!`` is interrupted by a process crash or
  when keys are modified outside Familia, creating both a memory leak
  and a data-resurface risk if identifiers are reused. Class-level
  related fields (``class_list``, etc.) are intentionally skipped
  because their keys have no instance segment. PR #221

Changed
-------

- ``health_check`` now accepts an ``audit_collections:`` keyword
  argument (default ``false``). When ``true``, the returned
  ``AuditReport`` includes a ``related_fields`` entry and
  ``complete?`` takes the new dimension into account. When omitted,
  ``related_fields`` is ``nil`` (signalling "not checked") and
  ``complete?`` reports ``false`` until the audit is opted into.
  PR #221

AI Assistance
-------------

- Implementation of ``audit_single_related_field`` and the
  ``AuditReport`` extensions for the new dimension were authored with
  AI assistance. Test coverage in
  ``try/audit/audit_related_fields_try.rb`` (31 testcases across
  healthy baselines, compound identifiers, multi-field orphans, mixed
  live/orphaned state, opt-in wiring, and class-level skip) was
  produced in parallel.
