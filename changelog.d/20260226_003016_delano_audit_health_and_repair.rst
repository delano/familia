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

- Participation audit now reads the actual collection contents instead
  of the instances timeline. Class-level collections are read via
  ``membersraw``; instance-level collections are discovered by SCAN
  and read with type-appropriate commands (ZRANGE, SMEMBERS, LRANGE).
  Repair uses TYPE introspection to dispatch ZREM, SREM, or LREM on
  the specific collection key reported by the audit.

Changed
-------

- ``find_by_dbkey`` and ``find_by_identifier`` are now read-only.
  They no longer call ``cleanup_stale_instance_entry`` as a side effect
  when a key is missing. Ghost cleanup is the explicit responsibility
  of the audit/repair layer or direct caller invocation.
  ``cleanup_stale_instance_entry`` is now a public class method.

- Fast writers (``field!``), ``batch_update``, ``batch_fast_write``,
  and ``save_fields`` now clear dirty tracking state after a successful
  database write, so ``dirty?`` accurately reflects unsaved changes.

AI Assistance
-------------

- Implementation, test authoring, and iterative debugging performed
  with Claude Opus 4.6 assistance. The plan was authored collaboratively
  and executed across multiple sessions covering code, 211 test cases
  across 14 audit files, and this changelog fragment.
