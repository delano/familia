Documentation
-------------

- Added a tryout covering the split-identifier unique index corruption case:
  ``audit_unique_indexes`` surfacing the disagreement, ``rebuild_<name>_index``
  repairing it, guard auto-validation on save, idempotent rebuilds, multi-index
  isolation, phantom + missing combinations, dual disagreement via
  ``:value_mismatch``, and nil/empty indexed-value handling. (#243)

AI Assistance
-------------

- Claude Code (Opus 4.7) drafted the new ``unique_index_split_identifier_try.rb``
  tryout, including scenario coverage and corruption-seeding helpers, and
  iterated on the expectations against live behavior of ``audit_unique_indexes``
  and ``rebuild_name_index``. (#243)
