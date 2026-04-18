Added
-----

- Cross-registry drift detection for Horreum models. ``audit_cross_references``
  walks every live identifier in the ``instances`` sorted set and cross-checks
  each class-level unique index, surfacing two drift modes that per-registry
  audits cannot catch alone:
  ``in_instances_missing_unique_index`` (live object has a populated indexed
  field but no corresponding index entry) and
  ``index_points_to_wrong_identifier`` (index entry exists but references a
  different identifier, i.e. split-brain). Instance-scoped unique indexes and
  multi-indexes are out of scope; multi-index coverage lives in
  ``audit_multi_indexes``. PR #221

Changed
-------

- ``health_check`` now accepts a ``check_cross_refs:`` keyword argument
  (default ``false``). When ``true``, the returned ``AuditReport`` includes
  a ``cross_references`` entry and ``complete?`` takes the new dimension
  into account. When omitted, ``cross_references`` is ``nil`` (signalling
  "not checked") and ``complete?`` reports ``false`` until the audit is
  opted into. This keeps the default ``health_check`` fast while making
  the deeper cross-registry audit available on demand. PR #221

AI Assistance
-------------

- Implementation of ``audit_cross_references`` and the ``AuditReport``
  extensions for the new dimension were authored with AI assistance. Test
  coverage in ``try/audit/audit_cross_references_try.rb`` (37 testcases
  across empty-index, healthy baselines, forward drift, split-brain,
  nil/empty field skip, multiple unique indexes per class, instance-scoped
  index skip, health_check opt-in wiring, and AuditReport nil/populated
  states) was produced in parallel.
