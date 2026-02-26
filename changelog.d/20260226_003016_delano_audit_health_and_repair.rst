Added
-----

- Proactive consistency audit infrastructure for Horreum models. Every
  subclass now has ``health_check``, ``audit_instances``,
  ``audit_unique_indexes``, ``audit_multi_indexes``, and
  ``audit_participations`` class methods to detect phantoms (timeline
  entries without backing keys), missing entries (keys not in timeline),
  stale index entries, and orphaned participation members. Issue #221.

- ``AuditReport`` data structure (``Data.define``) that wraps audit
  results with ``healthy?``, ``to_h`` (summary counts), and ``to_s``
  (human-readable) methods for quick inspection and programmatic use.

- Repair and rebuild operations: ``repair_instances!``,
  ``rebuild_instances``, ``repair_indexes!``,
  ``repair_participations!``, and ``repair_all!`` class methods.
  ``rebuild_instances`` performs a full SCAN-based rebuild with atomic
  swap via the existing ``RebuildStrategies`` infrastructure.

- ``scan_keys`` helper on ManagementMethods for production-safe
  enumeration of keys matching a class pattern via SCAN.

AI Assistance
-------------

- Implementation, test authoring, and iterative debugging performed
  with Claude Opus 4.6 assistance. The plan was authored collaboratively
  and executed in a single session covering code, 112 test cases across
  9 files, and this changelog fragment.
