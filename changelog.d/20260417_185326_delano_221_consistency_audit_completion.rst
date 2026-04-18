Added
-----

- ``repair_related_fields!`` class method on every Horreum model. Given
  results from ``audit_related_fields`` (or running a fresh audit when
  called with no argument), it DELs every orphaned collection key and
  returns ``{removed_keys:, failed_keys:, status:}``. Failures from
  ``Redis::CommandError`` are captured per key so a single bad key does
  not abort the batch. ``repair_all!`` now calls into the new method
  when the report's ``related_fields`` dimension is populated, matching
  the opt-in semantics of ``health_check(audit_collections: true)``:
  repairs only what the caller asked to audit. Progress callbacks emit
  ``phase: :repair_related_fields`` with ``current``/``total`` counts.
  PR #221

AI Assistance
-------------

- Implementation of ``repair_related_fields!`` and its integration into
  ``repair_all!``, plus the regression coverage in
  ``try/audit/repair_related_fields_try.rb`` (16 testcases across clean
  state, single orphan, multi-field orphans, mixed live/crashed
  instances, pre-computed audit input, progress callback wiring,
  ``repair_all!`` opt-in semantics, and idempotency), were authored
  with AI assistance.
