Changed
-------

- Audit methods now pipeline batched Redis operations to reduce round
  trips. ``audit_cross_references`` collects ``(identifier,
  field_value)`` pairs per unique index per batch and resolves them
  with a single HMGET instead of one HGET per object per index.
  ``discover_multi_index_buckets`` (multi-index audit) and
  ``audit_single_related_field`` (orphaned collection key audit) now
  batch SCAN results in slices of 100 and issue SMEMBERS and EXISTS
  calls inside a ``dbclient.pipelined`` block respectively, collapsing
  M round trips into roughly M/100. Return shapes and semantics are
  unchanged. PR #221

Fixed
-----

- Multi-index audit now respects ``Familia.delim`` when constructing
  SCAN patterns for per-value bucket keys. Previously the bucket
  pattern and prefix in ``discover_multi_index_buckets`` hardcoded
  ``:`` as the delimiter, so deployments configured with a custom
  ``Familia.delim`` would match zero keys during SCAN and silently
  report a clean multi-index audit even when orphans or drift
  existed. PR #221

- ``audit_instance_participations`` now also respects
  ``Familia.delim`` when constructing its collection-key SCAN
  pattern. The initial delimiter fix in
  ``discover_multi_index_buckets`` and ``audit_single_related_field``
  missed this third call site, so instance-level participation
  audits continued to silently return no stale members under a
  non-default delim. PR #221

- ``Horreum.scan_pattern`` now respects ``Familia.delim`` instead of
  hardcoding ``:``. This pattern underlies ``scan_identifiers``, the
  canonical "enumerate all live instances" helper used by
  ``audit_instances``, the missing-phase of
  ``audit_unique_indexes`` and ``audit_multi_indexes``, and
  indirectly ``audit_cross_references``. Under a custom delim every
  one of these audits silently saw zero live objects and reported
  clean. PR #221

AI Assistance
-------------

- The four audit performance and correctness fixes above
  (delimiter-aware SCAN pattern, batched HMGET in
  ``audit_cross_references``, pipelined SMEMBERS in
  ``discover_multi_index_buckets``, pipelined EXISTS in
  ``audit_single_related_field``) along with the
  ``deserialize_index_value`` helper were authored with AI
  assistance.
