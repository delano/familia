Added
~~~~~

- Instance-scoped ``audit_multi_indexes`` is now fully implemented.
  Discovers per-scope bucket keys via SCAN, partitions them by scope
  instance, and reports stale members, orphaned buckets, and missing
  entries in the same shape as the class-level audit. Orphan entries
  carry a ``:reason`` (``:scope_missing`` or ``:field_value_unheld``)
  and a ``:scope_id``. Missing entries are detected via the indexed
  class's ``participates_in`` relationship to the scope class; when
  absent, the result carries ``missing_status: :not_audited``.
  Resolves the ``:not_implemented`` follow-up from #217.

- ``repair_multi_indexes!`` class method that invokes the existing
  ``rebuild_<index_name>`` methods for both class-level (one call on
  the indexed class) and instance-scoped (one call per scope
  instance) multi-indexes. Indexes whose audit status is ``:ok`` are
  skipped; rebuild methods that don't exist or scope classes
  without an ``instances`` collection are recorded in ``:skipped``
  with a reason.

Changed
~~~~~~~

- ``repair_all!`` now runs each repair stage inside its own rescue
  boundary; a failure in one dimension no longer prevents the others
  from running. The return hash gains ``:status`` (``:ok`` or
  ``:partial_failure``), ``:errors`` (per-stage exception details
  when raised), and ``:multi_indexes`` (results from the new
  ``repair_multi_indexes!``). An opt-in ``verify: true`` kwarg
  re-runs ``health_check`` after repair and exposes the result as
  ``:post_audit`` / ``:verified`` so callers can confirm the run
  actually drove the model back to a healthy state.

- ``AuditReport#complete?`` is no longer false-positive due to
  ``:not_implemented`` stubs in ``multi_indexes`` -- instance-scoped
  indexes return ``:ok`` or ``:issues_found`` like class-level ones.

AI Assistance
~~~~~~~~~~~~~

- Instance-scoped multi-index audit algorithm (bucket discovery,
  scope existence batching, participation-driven missing detection),
  ``repair_multi_indexes!``, the ``repair_all!`` robustness
  refactor, and the accompanying tryouts coverage were authored
  with Claude Code assistance against the #217 review branch.
