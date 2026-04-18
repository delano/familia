Changed
-------

- ``health_check`` now computes the underlying ``scan_identifiers`` and
  ``load_multi`` passes a single time and threads the results through
  ``audit_unique_indexes`` and ``audit_multi_indexes`` so every
  sub-audit reuses them during its "missing entries" phase. A model
  with N class-level unique indexes and M class-level multi indexes
  previously triggered ``1 + N + M`` SCANs (plus the ``audit_instances``
  scan) per ``health_check`` invocation; it now triggers ``2`` SCANs
  regardless of how many indexes the model declares. Behavior and
  return shapes are unchanged. PR #221

AI Assistance
-------------

- The caching refactor and corresponding standalone regression
  testcases were authored with AI assistance.
