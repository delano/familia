Added
-----

- Class-level multi-index consistency auditing. ``audit_multi_indexes``
  now detects drift in class-level multi-indexes through a three-phase
  sweep: stale members whose indexed object is missing or whose field
  value no longer matches the bucket, live objects missing from their
  expected bucket, and orphaned buckets for field values no live object
  holds. Each result carries a ``status`` of ``:ok``, ``:issues_found``,
  or ``:not_implemented``. Instance-scoped indexes (``within:
  SomeClass``) continue to return ``:not_implemented`` until scope
  enumeration is available. PR #221

AI Assistance
-------------

- Implementation of ``audit_class_level_multi_index`` and its three
  phase helpers (discover, detect stale, detect missing, detect
  orphaned) was authored with AI assistance. Test coverage in
  ``try/audit/m3_multi_index_stub_try.rb`` was expanded in parallel.
