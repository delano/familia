.. Changelog fragment for instance registry consistency and observability fixes.
.. Source: billing issues audit (2025-02 production investigation).

Fixed
-----

- ``commit_fields``, ``batch_update``, ``save_fields``, and fast writers now
  register objects in the ``instances`` sorted set via ``ensure_registered!``.
  Previously, only ``save`` added to the registry, leaving objects created
  through other write paths invisible to ``instances.to_a`` enumeration.

- Class-level ``destroy!`` now removes the identifier from the ``instances``
  sorted set, preventing ghost entries after deletion.

- ``find_by_dbkey`` lazily prunes ghost entries from ``instances`` when a hash
  key no longer exists (TTL expiry or external deletion).

Added
-----

- ``ensure_registered!`` and ``unregister!`` instance methods for explicit
  registry management. ``ensure_registered!`` is idempotent (ZADD updates
  the timestamp without duplicating).

- ``registered?(identifier)`` class method for O(log N) membership checks
  against the ``instances`` sorted set without loading the object.

- Dirty tracking for scalar fields: ``dirty?``, ``dirty_fields``,
  ``changed_fields``, ``clear_dirty!``. Setters automatically mark fields
  dirty; state is cleared after ``save``, ``commit_fields``, and ``refresh!``.

- ``warn_if_dirty!`` guard on collection write methods (``add``, ``push``,
  ``[]=``, ``value=``). Warns when the parent Horreum has unsaved scalar
  changes. Enable ``Familia.strict_write_order = true`` to raise instead.

- ``ttl_report`` instance method on Expiration-enabled models. Returns a hash
  showing TTL for the main key and all relation keys, useful for detecting
  TTL drift.

- ``debug_fields`` instance method on Horreum. Returns a diagnostic hash
  showing Ruby value, stored JSON, and type for each persistent field.

Documentation
-------------

- Added serialization encoding guide to CLAUDE.md showing how each DataType
  serializes values and what raw Redis output looks like per type.

AI Assistance
-------------

- Implementation, testing, and documentation performed with Claude Opus 4.6
  assistance across dirty tracking, write-order guards, TTL reporting,
  debug_fields, instance registry tests, and ghost object tests.
