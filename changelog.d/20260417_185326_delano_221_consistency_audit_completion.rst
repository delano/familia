Added
-----

- ``repair_related_fields!`` class method on every Horreum model. Given
  results from ``audit_related_fields`` (or running a fresh audit when
  called with no argument), it DELs every orphaned collection key and
  returns ``{removed_keys:, failed_keys:, status:}``. Failures from
  ``Redis::CommandError`` are captured per key so a single bad key does
  not abort the batch. ``repair_all!`` accepts two new opt-in keyword
  arguments -- ``audit_collections:`` and ``check_cross_refs:`` -- that
  are threaded through to ``health_check``. When
  ``audit_collections: true`` the report carries a populated
  ``related_fields`` dimension and ``repair_all!`` calls
  ``repair_related_fields!`` on it. When ``check_cross_refs: true`` the
  report carries a populated ``cross_references`` dimension for
  inspection; no automatic repair is performed for cross-reference drift
  and callers must resolve it manually. Defaults for both kwargs are
  ``false`` so existing callers see unchanged behaviour. Progress
  callbacks emit ``phase: :repair_related_fields`` with
  ``current``/``total`` counts. PR #221

AI Assistance
-------------

- Implementation of ``repair_related_fields!`` and its integration into
  ``repair_all!``, plus the regression coverage in
  ``try/audit/repair_related_fields_try.rb`` (19 testcases across clean
  state, single orphan, multi-field orphans, mixed live/crashed
  instances, pre-computed audit input, progress callback wiring,
  ``repair_all!`` opt-in semantics, end-to-end opt-in repair, the
  ``Redis::CommandError`` failure path, side-effect isolation from
  ``instances``/indexes, and idempotency), were authored with AI
  assistance.
