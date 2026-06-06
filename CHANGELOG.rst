CHANGELOG.rst
=============

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-2.10.1:

2.10.1 — 2026-06-06
===================

Added
-----

- ``record_class:`` option for collection DataTypes (``list``/``set``/
  ``sorted_set``/``hashkey``). This loading-only hint tells ``each_record`` which
  class to hydrate via ``load_multi`` without changing how the collection
  serializes or deserializes reads. Use this when you want ``each_record`` lookup
  behavior but no changes to read behavior. Issue #297

- ``Familia.atomic_write(*instances)`` persists multiple Horreum instances in a
  single ``MULTI/EXEC``. Includes an optional ``watch_keys:``/``pre_check:``
  variant for race-safe, write-once semantics. All participating instances must
  resolve to the same logical database (raising ``Familia::CrossDatabaseError``
  otherwise) and must share a hash slot on Redis Cluster. #296

Changed
-------

- ``participates_in`` / ``class_participates_in`` collections now default to
  using ``record_class:``. This change requires **no data migration and causes no
  behavior changes**: existing collections already stored raw identifiers, and
  read operations (``members``, ``to_a``, ``member?``, ``score``) behave exactly
  as before. The only difference is that ``each_record`` is now supported. Pre-
  declared collections are left untouched. Issue #297

Fixed
-----

- Enabled ``each_record`` on ``participates_in`` and ``class_participates_in``
  collections by automatically declaring them with ``record_class: <participant
  class>``. This resolves ``Familia::Problem`` exceptions and loads participant
  records via ``load_multi`` across all collection types. Issue #297

- Suppressed per-member ``[deserialize] Raw fallback`` warning storm when
  iterating ``record_class`` collections with non-JSON identifiers (such as UUIDs
  or prefixed IDs). These expected raw values are now logged at the debug level
  instead of warnings. Issue #297

- Resolved a connection-pooling bug where the ``WATCH``-based optimistic lock
  in ``atomic_write(watch_keys:)``, ``save_if_not_exists!``, and ``create!`` was
  silent/inert. The ``WATCH`` and ``MULTI/EXEC`` commands are now driven through
  the same connection, ensuring concurrent modifications correctly abort and raise
  as
  documented. #296

  AI Assistance
  -------------

  - AI diagnosed the participation iteration bug and identified that ``reference: true``
    introduced unintended read-behavior changes. Designed and implemented the
    ``record_class:`` option to decouple ``each_record`` lookup from read deserialization,
    suppressed a resulting per-member deserialize warning storm, kept intentional
    raw-string semantics on ``instances`` and ``unique_index``, updated stale
    flowcharts in ``datatype-collections.md``, and added regression coverage. Issue #297

  - Root-caused and fixed a split-connection defect with Claude Code: implemented a
    single-connection ``execute_watched_transaction`` primitive (avoiding fiber-pinning
    that degrades atomic commands) and added real concurrent-modification tests to
    replace simulated aborts. #296

  - Designed and built multi-model atomic writes on top of the new ``WATCH`` primitive:
    implemented the same-database guard, orchestration logic, and a test suite covering
    two-model commits, rollback on error, cross-database rejection, and race conditions. #296

.. _changelog-2.10.0:

2.10.0 — 2026-06-04
====================

Added
-----

- ``Horreum.build``: A factory block that yields a new instance, then commits
  all scalar and collection changes in a single ``MULTI/EXEC`` upon exit.
  This avoids sequencing ``save`` before collection writes. Raises
  ``Familia::RecordExistsError`` if the identifier exists (create-only).
  Without a block, it behaves as ``new(...).save``. #279

- ``atomic_write`` now supports ``watch_keys:`` (keys to watch) and
  ``pre_check:`` (a callable run between ``WATCH`` and ``MULTI``) to enable
  optimistic locking. Retries with exponential backoff on abort. #288

- ``encrypted_field`` now accepts a ``key_material:`` proc. This mixes
  additional entropy into key derivation (separate from AAD), requiring
  the correct material at decryption to avoid producing garbage output. PR #280

- Encrypted-field envelopes now store their own ``envelope_version`` and
  ``aad_fields`` list. Decryption rebuilds AAD from these stored fields
  rather than the active class declaration, preventing breakage when model
  definitions change. PR #280

- ``DatabaseLogger.capture_enabled`` (Boolean, default ``true``) controls
  in-memory buffer capturing. Disabling it bypasses clock checks, message
  allocations, and buffer appends, offering a zero-overhead production path. Issue #233

- ``Familia::Instrumentation.hooks?(type)`` reports whether hooks are
  registered for a given event type (e.g. ``:command``, ``:pipeline``). Issue #233

- ``Familia.reset_trace!`` clears the cached trace environment lookup. Issue #233

- ``dirty_write_warnings`` class method configures write-order warnings per
  class (inheritable). Accepts ``:strict``, ``:warn``, ``:once``, or ``:off``. Issue #277

- ``Familia.dirty_write_warnings`` global setting providing the default mode for
  classes that do not set their own. Issue #277

- ``Familia.raise_on_unsaved_parent_write`` (default ``true``) controls whether a
  collection write on a new, unsaved, dirty parent raises or warns. Issue #278

Changed
-------

- Mutating a collection on a *new, unsaved* parent Horreum now **raises**
  ``Familia::Problem`` by default. The guard fires *before* the command runs,
  preventing orphaned data. Save the parent first, or set
  ``Familia.raise_on_unsaved_parent_write = false`` to restore warnings. Issue #278

- Dirty-write warnings are now **deduplicated per dirty window** (mode ``:once``).
  Writing to a collection on a parent with unsaved scalar fields warns once per
  distinct set of unsaved fields instead of on every write. Set
  ``dirty_write_warnings :warn`` to restore the old behavior. Issue #277

- Dirty-write warnings and strict raises now append the hint:
  ``(call #save first or wrap in atomic_write)``. Issue #277

- ``trace_enabled?`` now caches the ``FAMILIA_TRACE`` lookup. Use
  ``Familia.reset_trace!`` to force a re-read of the environment. Issue #233

- ``unique_index`` hashkeys now store identifiers as raw strings rather than
  JSON-encoded strings. Rebuild existing unique indexes to convert legacy entries,
  e.g., via ``User.rebuild_email_lookup`` or ``company.rebuild_badge_index``. Issue #276

Fixed
-----

- ``Horreum.build`` with a block no longer has a TOCTOU race between the
  ``exists?`` check and the ``atomic_write`` commit. The block path now uses
  ``atomic_write(watch_keys:, pre_check:)`` so the existence check runs between
  ``WATCH`` and ``MULTI``. #288

- ``aad_fields`` containing a ``transient_field`` now bind to the field's real
  value. Previously ``build_aad`` called ``RedactedString#to_s``, which returns
  ``"[REDACTED]"`` for every value -- so all passphrases produced identical AAD
  and the binding was defeated. PR #280

- ``each_record`` now works on ``unique_index`` hashkeys. Previously it raised
  ``Familia::Problem`` because ``unique_index`` created its backing hashkey
  without the ``class:`` option. Issue #276

- ``each_record`` extracts the stored identifier (the hash *value*) from a
  HashKey instead of the indexed field (the hash *key*). Issue #276

- The unguarded ``Familia.trace`` sites in ``Horreum#destroy!`` and
  ``find_by_dbkey`` now carry an inline ``if Familia.debug?`` guard. Issue #233

- Two latent encryption bugs surfaced while repairing the examples (issue #250):

  - ``Familia::Encryption.with_request_cache`` and ``clear_request_cache!``
    were unreachable. The implementation lived in
    ``lib/familia/encryption/request_cache.rb``, which was never ``require``\ d.
    The file is now loaded with the rest of the encryption stack.

  - The XChaCha20-Poly1305 provider derived keys with
    ``context.force_encoding('BINARY')``, mutating the caller's string. A
    frozen context raised ``FrozenError``. It now uses ``context.b``.

Security
--------

- The ``aad_fields`` transient-field fix changes AAD output for any field that
  lists a ``transient_field``. Values encrypted by an earlier release using a
  transient field in ``aad_fields`` were bound to ``"[REDACTED]"`` and will no
  longer decrypt after upgrading. Re-encrypt affected values if any exist.
  PR #280

Documentation
-------------

- Repaired every script in ``examples/`` so each runs top-to-bottom and is
  re-runnable (issue #250). Added ``try/integration/examples/`` with one
  subprocess-driven tryouts file per example script for automated regression
  coverage.

- ``Horreum.create!``: added ``@yield``, ``@yieldparam``, and
  ``@yieldreturn`` YARD tags documenting the post-success block semantics. #286

- ``Horreum#save``: added ``@example`` tags showing idiomatic Ruby patterns
  for post-save callbacks (``if save`` and ``&&`` short-circuit). #286

- Renamed ``CLAUDE.md`` to ``AGENTS.md`` and pruned it to remove volatile
  content better served by its source of truth. Kept the non-obvious behavioral
  contracts like deferred-vs-immediate write model and the serialization table.

AI Assistance
-------------

- AI implemented ``build`` factory block (#279) and WATCH composition in
  ``atomic_write`` (#288), including tryouts for both.

- AI refactored encryption envelope handling (#280): unified AAD construction
  through ``EncryptedData``, added envelope versioning, and fixed the
  transient-field AAD bypass.

- AI implemented ``DatabaseLogger.capture_enabled`` toggle and middleware
  consolidation (#233), per-class ``dirty_write_warnings`` (#277), and
  unsaved-parent guard (#278) with tryouts for each.

- AI diagnosed and fixed ``each_record`` on ``unique_index`` hashkeys (#276)
  and repaired all example scripts with regression tryouts (#250).

- AI evaluated and rejected ``save_and_then`` (#286) after cross-ORM analysis;
  added YARD docs and ``create_block_try.rb`` instead.

.. _changelog-2.9.1:

2.9.1 — 2026-05-18
==================

Added
-----

- ``SortedSet#update`` (aliased ``merge!``) for bulk member insertion. A sorted
  set is ``member => score`` -- the same pair shape as ``HashKey``'s
  ``field => value`` -- so it follows the established ``HashKey#update``/``merge!``
  convention (a single Hash argument) rather than the variadic splat used by the
  value-only ``UnsortedSet``/``ListKey``. Pass ``{member => score}`` to issue one
  ``ZADD`` instead of one round-trip per member. Validates the argument is a Hash
  and that every score is ``Numeric`` (a missing/``nil`` score raises a clear
  ``ArgumentError`` instead of a low-level client error -- unlike single-value
  ``#add``, the bulk path does not default a missing score to ``Familia.now``).
  Cascades expiration, and is a no-op returning ``0`` for empty input. The
  single-value ``SortedSet#add`` (and its array-as-single-member contract) is
  unchanged. PR #269

Changed
-------

- Bulk-write optimization for multi-value collection mutations. ``UnsortedSet#add``,
  ``ListKey#push``, and ``ListKey#unshift`` previously issued one Redis command per
  element (a loop of ``SADD``/``RPUSH``/``LPUSH`` calls), making large populations
  slow even when pipelined. They now serialize all values and issue a single bulk
  ``SADD``/``RPUSH``/``LPUSH`` command. Element ordering, ``nil`` compaction, nested
  array flattening, return values, dirty-write warnings, and expiration cascading
  are unchanged; empty calls remain no-ops. PR #269

AI Assistance
-------------

- AI investigated all collection ``DataType`` classes for the same per-element
  loop anti-pattern, identified the three affected methods, verified
  behavior-preservation (ordering, edge cases, chainability) at the Redis wire
  level, and confirmed zero regressions against the existing test suites. The
  ``SortedSet#update`` API shape was chosen by priority order: existing Familia
  conventions first (the ``HashKey#update``/``merge!`` precedent for keyed
  collections), then the upstream redis-rb bulk ``ZADD`` form, then Ruby
  ``Hash#merge!`` semantics as confirmation.

.. _changelog-2.9.0:

2.9.0 — 2026-05-17
==================

Added
-----

- Batch iteration primitives for DataTypes via ``Enumerable`` integration:

  - All DataTypes (``SortedSet``, ``HashKey``, ``UnsortedSet``, ``ListKey``) now
    ``include Enumerable``, providing ``each_slice``, ``lazy``, ``map``, ``reduce``,
    ``find``, and other stdlib methods.

  - **SortedSet#each(since:, until:)**: Cursor-based iteration with optional
    timestamp bounds. Uses ZRANGEBYSCORE when bounds provided (inclusive),
    ZSCAN otherwise. Accepts Time objects or numeric scores.

  - **HashKey#each(matching:)**: Cursor-based iteration via HSCAN with optional
    glob pattern filter on field names.

  - **UnsortedSet#each(matching:)**: Cursor-based iteration via SSCAN with optional
    glob pattern filter using Redis SSCAN MATCH on raw values.

  - **ListKey#each(batch_size:)**: Memory-efficient LRANGE pagination for large lists.

- ``DataType#each_record(batch_size:, write_size:, **filters)`` yields loaded
  Horreum records (not raw IDs) via ``load_multi``. Ghost instances (expired keys
  still in ``instances``) are automatically filtered. The ``write_size:`` parameter
  controls pipelining depth (``nil`` for serial execution).

- ``Familia::BatchResult`` value type for aggregating batch operation results:

  - ``BatchResult.collect(enumerable, strict: false) { |record| ... }`` iterates
    any Enumerable, tracking ``scanned``, ``modified`` (truthy returns), ``errors``
    (array of ``{id:, error:}``), and ``duration_ms``.

  - Per-record exception isolation: errors are captured and iteration continues.

  - ``strict: true`` re-raises collected errors after iteration completes.

Changed
-------

- Renamed batch field-update methods for clarity:

  - ``batch_update`` is now ``multi_field_update``
  - ``batch_fast_write`` is now ``multi_field_fast_write``

  Old names removed without deprecation shim (breaking change).

- Moved ``MultiResult`` into Familia namespace as ``Familia::MultiResult``.
  Old top-level constant removed without backwards-compat alias (breaking change).

AI Assistance
-------------

- Implementation and test coverage developed with parallel Claude Code agents:
  one for production code (DataType iteration, BatchResult, renames), one for
  Tryouts test suite (228 new tests across 8 files). PR #264.

.. _changelog-2.8.0:

2.8.0 — 2026-05-15
==================

Added
-----

- Expanded Redis 7 command coverage across all DataType classes:

  - **StringKey**: ``incrbyfloat``, ``getex``, ``getdel``, ``setex``, ``psetex``,
    ``bitcount``, ``bitpos``, ``bitfield``, plus class methods ``mget``, ``mset``,
    ``msetnx``, ``bitop`` for multi-key and bitwise operations.

  - **List**: ``trim``/``ltrim``, ``set``/``lset``, ``insert``/``linsert``,
    ``move``/``lmove``, ``pushx``/``rpushx``, ``unshiftx``/``lpushx``.
    Updated ``pop`` and ``shift`` to support optional count parameter for batch operations.

  - **UnsortedSet**: ``intersection``/``inter``, ``union``, ``difference``/``diff``,
    ``member_any?``/``members?``, ``scan``, ``intercard``/``intersection_cardinality``,
    ``interstore``/``intersection_store``, ``unionstore``/``union_store``,
    ``diffstore``/``difference_store``.

  - **SortedSet**: ``popmin``, ``popmax``, ``score_count``/``zcount``, ``mscore``,
    ``union``, ``inter``, ``rangebylex``, ``revrangebylex``, ``remrangebylex``,
    ``lexcount``, ``randmember``, ``scan``, ``unionstore``, ``interstore``,
    ``diff``, ``diffstore``.

  - **HashKey**: ``scan``/``hscan``, ``incrbyfloat``/``incrfloat``,
    ``strlen``/``hstrlen``, ``randfield``/``hrandfield``, plus field-level TTL
    commands (Redis 7.4+): ``expire_fields``, ``pexpire_fields``, ``expireat_fields``,
    ``pexpireat_fields``, ``ttl_fields``, ``pttl_fields``, ``persist_fields``,
    ``expiretime_fields``, ``pexpiretime_fields``.

- Added 158 new tests across 5 test files covering all new methods.

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

- ``housekeeping`` feature gains a class-level bulk runner,
  ``Klass.run_chores!(chore_name:, limit:, batch_size:)``. It iterates
  the class's ``instances`` collection in pipelined batches via
  ``load_multi``, runs all registered chores (or one named chore)
  against each record, and returns a stats hash:
  ``{ model:, scanned:, chores: { name => { modified:, errors: } } }``.
  Truthy chore returns increment ``modified``; raised exceptions are
  isolated per-record, logged via ``Familia.warn``, and counted as
  ``errors`` so a single failure doesn't halt the run. Lifted from the
  shape proven out in OneTime Secret's ``HousekeepingJob``.

- Trace events for connection-mode conflicts. ``Familia.trace`` now
  emits ``CONFLICTING_CONTEXT`` when pipeline and transaction
  contexts collide (in both ``FiberPipelineHandler``/
  ``FiberTransactionHandler`` and the
  ``execute_transaction``/``execute_pipeline`` entry points), and
  ``FAST_WRITER_BLOCKED`` when a fast writer (``field!``) is called
  inside a transaction or pipeline. These fire just before the
  corresponding ``ConflictingContextError`` /
  ``OperationModeError`` is raised, so operators can pinpoint where
  blocked operations originate when ``FAMILIA_TRACE=1``.

Changed
-------

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

- ``housekeeping`` feature: split the dual-purpose ``tidy!`` into two
  explicit instance methods. ``do_chore!(name)`` runs a single named
  chore and returns the block's raw return value (no longer wrapped
  in a ``{name => result}`` hash). ``do_chores!`` runs every
  registered chore and returns the ``{name => result}`` hash.
  ``tidy!`` is preserved as an alias of ``do_chores!`` for backwards
  compatibility with the 2.7.0 no-arg call site; the single-arg form
  ``tidy!(:name)`` now raises ``ArgumentError``.

- The connection handler hierarchy has been refactored from class
  inheritance (``BaseConnectionHandler``) to module composition.
  Handlers now ``include Familia::Connection::Handler`` and declare
  their operation-mode capabilities with a small DSL:
  ``supports transaction: true, pipelined: false``. The
  ``BaseConnectionHandler`` constant is gone. This is only relevant if
  you have custom handlers in application code — the public
  ``allows_transaction`` / ``allows_pipelined`` class methods continue
  to work, and the singleton ``.instance`` accessors on
  ``FiberPipelineHandler`` / ``FiberTransactionHandler`` are
  unchanged. The previous default of "allow all operations" when
  capability flags were not set has been removed; every handler is now
  expected to declare its capabilities explicitly via ``supports``.
- ``Familia.dbclient`` and ``Familia::DataType#dbclient`` now route through ``FiberPipelineHandler`` before ``FiberTransactionHandler``, matching ``Horreum#dbclient``. With both handlers in the chain, attempting to mix pipeline and transaction contexts raises ``Familia::ConflictingContextError`` uniformly from every call site.

Removed
-------

- ``Familia::DataType#direct_access`` has been removed. The method
  was a legacy escape hatch for issuing raw Redis commands from
  inside a DataType wrapper; it predates the chain-based routing of
  ``Fiber[:familia_transaction]`` and ``Fiber[:familia_pipeline]``.
  All in-tree call sites now go through the wrapper's own mutating
  methods (which auto-route through the active transaction or
  pipeline) or through the wrapper's ``transaction`` / ``pipelined``
  blocks. If you were calling ``direct_access do |conn, key| ... end``,
  replace it with either the DataType's own mutator or the
  corresponding block API.

Fixed
-----

- ``SortedSet#popmin`` and ``SortedSet#popmax`` now normalize an explicitly
  passed ``nil`` count to the default of ``1``. Previously, calling
  ``zset.popmin(nil)`` or ``zset.popmax(nil)`` would bypass the ``count == 1``
  branch of the structural dispatch added in the prior commit, causing
  redis-rb's flat ``[member, score]`` return shape to be iterated as if it
  were a nested result — yielding a malformed pair. Omitting the argument
  was and remains unaffected.

- Restored ``require 'set'`` in ``lib/familia/horreum/management/audit.rb``. ``Set`` is autoloaded as a core class only on Ruby 3.4+; on Ruby 3.2/3.3 (the gem's supported floor) the require is mandatory for the five ``Set.new`` usages in that file.

AI Assistance
-------------

- Claude Opus 4.5 analyzed Redis 7 command documentation and compared coverage
  against existing Familia DataType implementations using parallel Explore agents.
- Implementation performed by 5 parallel backend-dev agents, one per DataType.
- Test coverage written by 5 parallel qa-automation-engineer agents focusing on
  Familia-specific behavior (serialization, deserialization, aliases) rather than
  re-testing redis-rb gem functionality.

- Edge case identified by the Claude Code Review GitHub Action
  (``.github/workflows/claude-code-review.yml``) when reviewing the
  structural-dispatch change in commit ``010d5be``. Fix drafted and verified
  by Claude Opus 4.7 under supervision.

- Instance-scoped multi-index audit algorithm (bucket discovery,
  scope existence batching, participation-driven missing detection),
  ``repair_multi_indexes!``, the ``repair_all!`` robustness
  refactor, and the accompanying tryouts coverage were authored
  with Claude Code assistance against the #217 review branch.

- Method split, alias wiring, bulk runner port from OTS, doc updates,
  and expanded tryouts coverage (25 → 48 testcases) authored with
  Claude Code.

- Added the trace instrumentation in response to PR #263 review
  feedback (Claude Code review bot) recommending tracing for
  conflict detection events.

- The handler refactor, ``direct_access`` removal, and changelog drafting were performed with Claude Code assistance while resolving review feedback on PR #263.

.. _changelog-2.7.0:

2.7.0 — 2026-05-13
==================

Added
-----

- New ``housekeeping`` feature for ``Familia::Horreum``: a declarative DSL
  (``chore :name do |obj| ... end``) for registering named cleanup blocks on
  a model class, plus an instance method ``tidy!`` that runs all (or one)
  registered chore against a single object. The feature owns registration
  and per-instance execution only -- iteration, batching, scheduling and
  error aggregation are the consumer application's responsibility, keeping
  it distinct from ``Familia::Migration`` (which is for versioned, one-shot
  transformations). Resolves #258.

Documentation
-------------

- Added ``docs/guides/feature-housekeeping.md`` covering the API, the
  ``housekeeping`` vs ``migration`` vs defensive-setter trade-off,
  generated method reference, design constraints, and common patterns
  (multiple chores, sequential steps in one chore, tracking modified
  records, error aggregation).

AI Assistance
-------------

- Drafted the housekeeping feature module, the tryouts test suite, and the
  guide using Claude Code, working from the API proposal in issue #258 and
  the existing ``feature-relationships.md`` and ``safe_dump.rb`` as style
  templates.

.. _changelog-2.6.0:

2.6.0 — 2026-04-17
==================

Added
-----

- ``audit_multi_indexes`` detects drift in class-level multi-indexes via a
  three-phase sweep (stale members, missing live objects, orphaned buckets).
  Instance-scoped indexes (``within:``) return ``:not_implemented``. PR #221

- ``audit_related_fields`` SCANs for instance-level collection keys
  (``list``, ``set``, ``zset``, ``hashkey``) whose parent hash no longer
  exists -- typically left behind by interrupted ``destroy!`` calls or
  external key mutation. Class-level related fields are skipped. PR #221

- ``audit_cross_references`` walks live identifiers against class-level
  unique indexes to surface drift modes per-registry audits miss:
  ``in_instances_missing_unique_index`` and
  ``index_points_to_wrong_identifier`` (split-brain). PR #221

- ``repair_related_fields!`` class method DELs orphaned collection keys
  from an audit result and returns ``{removed_keys:, failed_keys:,
  status:}``. ``repair_all!`` gains opt-in ``audit_collections:`` and
  ``check_cross_refs:`` kwargs (both default ``false``); only
  ``related_fields`` is auto-repaired, cross-reference drift is
  reported for manual resolution. PR #221

- ``Familia::AtomicOperations`` module exposing ``atomic_swap`` and
  ``build_temp_key`` as reusable primitives for rebuild-then-swap
  workflows (relies on native ``RENAME`` atomicity). PR #221

- ``Horreum#atomic_write(&block)`` wraps scalar persistence and
  collection mutations in a single MULTI/EXEC. Unlike
  ``save_with_collections``, failures roll back scalars too. All
  participating DataTypes must share ``logical_database``; mismatches
  raise ``Familia::CrossDatabaseError``. (#220)

Changed
-------

- ``health_check`` accepts new opt-in kwargs ``audit_collections:`` and
  ``check_cross_refs:`` (both default ``false``). When omitted, the
  corresponding report dimensions are ``nil`` and ``complete?`` returns
  ``false`` until opted in. PR #221

- ``atomic_swap`` and ``build_temp_key`` relocated from
  ``Indexing::RebuildStrategies`` to ``Familia::AtomicOperations``.
  Internal callers delegate through; downstream direct callers should
  switch. Semantics preserved verbatim from PR #247. PR #221

- ``health_check`` now reuses a single ``scan_identifiers`` +
  ``load_multi`` pass across unique- and multi-index audits, reducing
  SCANs from ``1 + N + M`` to ``2`` regardless of declared indexes.
  Behavior and return shapes unchanged. PR #221

- Audit methods pipeline batched Redis calls: ``audit_cross_references``
  uses HMGET per batch instead of per-object HGET;
  ``discover_multi_index_buckets`` and ``audit_single_related_field``
  batch SCAN results in slices of 100 inside ``pipelined`` blocks,
  collapsing M round trips to ~M/100. PR #221

Fixed
-----

- ``AuditReport#healthy?`` now considers multi-index ``missing`` entries;
  ``to_h`` / ``to_s`` include the ``missing`` count. Previously a report
  could show ``issues_found`` while ``healthy?`` returned true. PR #221

- ``atomic_write`` cross-database guard no longer false-positives when a
  Horreum inherits its ``logical_database`` and a related field explicitly
  sets ``logical_database: 0``. Both sides now resolve to concrete
  integers before comparison. (#220)

- ``atomic_write`` same-instance re-entrancy guard now uses a module-level
  ``Mutex`` to serialise the ``@atomic_write_owner`` check-then-set,
  closing a narrow race between concurrent entries. (#220)

- ``atomic_write`` clears the dirty flag only when
  ``MultiResult.successful?`` is true. Previously transactions whose
  individual commands returned exception objects (MULTI swallows these)
  could leave the object marked clean. (#220)

- ``Horreum.scan_pattern``, ``discover_multi_index_buckets``, and
  ``audit_instance_participations`` now respect ``Familia.delim`` instead
  of hardcoding ``:``. Under a custom delim, every audit grounded in
  these SCANs (instances, unique, multi, cross-references, participations)
  silently saw zero keys and reported clean. PR #221

AI Assistance
-------------

- Implementation and test coverage for the new audit dimensions
  (``audit_multi_indexes``, ``audit_related_fields``,
  ``audit_cross_references``, ``repair_related_fields!``), the
  ``AuditReport`` extensions, the ``healthy?``/``to_h``/``to_s`` fix, the
  ``Familia::AtomicOperations`` extraction, the ``health_check`` caching
  refactor, and the four audit performance/correctness fixes
  (delimiter-aware SCAN, batched HMGET, pipelined SMEMBERS, pipelined
  EXISTS) were authored with AI assistance. PR #221

- ``atomic_write`` design, implementation, tests, and review were
  coordinated across Claude Code agents (``feature-dev:code-architect``,
  ``backend-dev``, ``qa-automation-engineer``,
  ``feature-dev:code-reviewer``). The reviewer caught a silent-corruption
  gap in the cross-database guard; follow-up fixes (false-positive guard,
  re-entrancy race, MultiResult success semantics) were surfaced by
  ``gemini-code-assist`` and verified by the QA and reviewer agents. (#220)

.. _changelog-2.5.0:

2.5.0 — 2026-04-17
==================

Changed
-------

- ``Familia::RecordExistsError`` now exposes ``#existing_id`` and appends
  ``(existing_id=<id>)`` to its message when raised by the unique-index
  guards in ``guard_unique_indexes!``. Diagnosing stale-index drift no
  longer requires a secondary ``HGET`` to compare the drifted identifier
  against the one on the record being saved. The attribute defaults to
  ``nil`` and the message format is unchanged when absent, so existing
  rescue patterns and the primary-key collision raised by
  ``save_if_not_exists!`` are untouched. Issue #242.

- Instance-scoped index entries (``unique_index`` / ``multi_index``
  declared with ``within: SomeClass``) remain orphaned after ``destroy!``.
  This is a known limitation carried over from prior releases and now
  tracked separately as issue #244. Until that issue is closed, callers
  using instance-scoped indexes should remove entries explicitly (e.g.,
  ``employee.remove_from_company_badge_index(company)``) before
  ``destroy!``.

Fixed
-----

- **Encryption**: Fixed ``re_encrypt_fields!`` silently failing to re-encrypt fields under the current key version. Previously the method passed the existing ``ConcealedString`` back through the setter, which the setter preserves as-is for rehydration purposes, so no re-encryption occurred and the stored ciphertext retained its original ``key_version``. The method now reveals plaintext via ``ConcealedString#reveal`` and re-assigns it, forcing encryption under the current key version and algorithm. Issue #235

- ``Horreum#destroy!`` now cleans up class-level ``unique_index`` and
  ``multi_index`` entries within the same transaction that deletes the
  object hash and removes it from the ``instances`` timeline. Previously,
  stale entries remained and caused ``RecordExistsError`` on a subsequent
  ``create!`` with the same indexed value. Issue #241.

- Aligned ``guard_unique_indexes!`` with the ``within`` filter used by
  ``auto_update_class_indexes`` and the new ``remove_from_class_indexes!``
  helper, keeping validate/update/cleanup paths symmetric for any future
  ``unique_index`` declared ``within: :class``.

- Eliminated a transient read window during index rebuilds where concurrent
  ``HGET`` on an index key could return ``nil``. ``RebuildStrategies.atomic_swap``
  previously ran ``DEL`` followed by ``RENAME`` as two separate commands, leaving
  the final key absent in between. It now relies on ``RENAME``'s native atomic
  replacement, so readers never observe a missing index during rebuild. Issue #247

Security
--------

- **Encryption**: Key rotation via ``re_encrypt_fields!`` was a silent no-op for fields already loaded as ``ConcealedString`` (the normal case for objects rehydrated from Redis). Callers who followed the documented rotation workflow -- load, ``re_encrypt_fields!``, ``save`` -- left data encrypted under old, potentially compromised keys while believing rotation had succeeded. The stored ciphertext's ``key_version`` remained unchanged. Issue #235

Documentation
-------------

- Clarified in both ``docs/guides/encryption.md`` and ``docs/guides/feature-encrypted-fields.md`` that ``re_encrypt_fields!`` mutates in-memory state only and requires an explicit ``save`` to persist. Reworked the key rotation example in ``examples/encrypted_fields.rb`` to demonstrate the real rotation flow (save under v1, add v2, load fresh, re-encrypt, save) rather than pre-assigning plaintext (which masked the bug). Issue #235

- Added a tryout covering the split-identifier unique index corruption case:
  ``audit_unique_indexes`` surfacing the disagreement, ``rebuild_<name>_index``
  repairing it, guard auto-validation on save, idempotent rebuilds, multi-index
  isolation, phantom + missing combinations, dual disagreement via
  ``:value_mismatch``, and nil/empty indexed-value handling. (#243)

AI Assistance
-------------

- Collaborated with Claude on isolating the no-op root cause (the setter's ConcealedString-preservation branch), drafting the raw-envelope regression canary that inspects ``key_version`` in stored JSON, reworking ``examples/encrypted_fields.rb`` to exercise the real rotation flow rather than pre-assigning plaintext, and adding edge-case coverage for nonce freshness, missing-old-key failures, type-guard assertions, and mixed encrypted/plain/transient field models. Issue #235

- Implementation and test coverage drafted with Claude Code
  (backend-dev + qa-automation-engineer subagents), reviewed by
  feature-dev:code-reviewer.

- Claude Code (Opus 4.7) drafted the new ``unique_index_split_identifier_try.rb``
  tryout, including scenario coverage and corruption-seeding helpers, and
  iterated on the expectations against live behavior of ``audit_unique_indexes``
  and ``rebuild_name_index``. (#243)

- Issue triage, code review, failing-tryout authoring, and implementation
  were coordinated across several specialized Claude Code agents
  (qa-automation-engineer for test coverage, backend-dev for the fix,
  feature-dev:code-reviewer for verification of transaction atomicity
  and filter symmetry).

- Issue triage, fix, and race-detection test authored with Claude Code
  assistance. Issue #247

.. _changelog-2.4.0:

2.4.0 — 2026-04-06
==================

Added
-----

- Added ``staged:`` option to ``participates_in`` for invitation workflows where
  through models must exist before participants. Creates a staging sorted set
  alongside the active membership set with three new operations:
  ``stage_members_instance``, ``activate_members_instance``, ``unstage_members_instance``.
  Staged models use UUID keys; activated models use composite keys.
  (`#237 <https://github.com/delano/familia/issues/237>`_)

- Added ``StagedOperations`` module in ``lib/familia/features/relationships/participation/``
  for staging lifecycle management with lazy cleanup for ghost entries.

- Added ``staged?`` and ``staging_collection_name`` methods to ``ParticipationRelationship``.

Changed
-------

- **Breaking change**: Through models in staged relationships use UUID keys during staging,
  composite keys after activation. The staged model is destroyed during activation --
  any references to it become invalid. Application code calling ``accept!`` on
  staged memberships should capture and use the returned activated model rather
  than the original staged model.

- Extended ``participates_in`` signature to accept ``staged:`` option (Symbol or nil).
  Validation ensures ``staged:`` requires ``through:`` option.

AI Assistance
-------------

- Claude assisted with architecture design, identifying the impedance mismatch between
  relational ORM patterns and Redis's materialized indexes, analyzing transaction
  boundaries, and designing the separation between ``StagedOperations`` and
  ``ThroughModelOperations`` modules.

.. _changelog-2.3.3:

2.3.3 — 2026-03-30
==================

Added
-----

- Encrypt now records the original plaintext encoding in the EncryptedData
  envelope (``encoding`` field), completing the Phase 2 encoding round-trip
  fix. Decrypt (Phase 1, #228) already falls back to UTF-8 when the field
  is absent, so this change is backward-compatible. PR #229

Fixed
-----

- ``build_aad`` now produces consistent AAD (Additional Authenticated Data)
  regardless of whether the record has been persisted. Previously, encrypted
  fields with ``aad_fields`` used different AAD computation paths before and
  after save, making ``reveal`` fail on any record created via ``create!``.
  Issue #232, PR #234. No migration needed — the previous behavior was
  broken (AAD mismatch prevented decryption), so no valid ciphertexts
  exist under the old inconsistent paths.

- ``build_aad`` no longer uses ``.compact`` on AAD field values. Previously,
  nil fields were silently dropped, shifting later values left and producing
  a different hash once the field was populated. Now each field is coerced
  via ``.to_s`` so that nil and empty string both occupy a fixed position
  in the joined AAD string. Issue #232, PR #234.

AI Assistance
-------------

- Implementation and test authoring delegated to backend-dev agents, with
  orchestration and Phase 1 test fixups handled in the main session. Claude
  Opus 4.6.

- Claude assisted with implementing the fix, updating affected tests, and
  writing the round-trip regression test. The issue analysis, root cause
  identification, and suggested fix were provided in the issue by the author.

.. _changelog-2.3.2:

2.3.2 — 2026-03-12
==================

Fixed
-----

- ``Manager#decrypt`` no longer returns ASCII-8BIT strings. Decrypted plaintext
  is now force-encoded to UTF-8 by default, fixing compatibility with json 2.18+
  (which rejects non-UTF-8 strings) and preventing a hard error in json 3.0.
  When an ``encoding`` field is present in the encrypted envelope, that encoding
  is used instead. Fixes `#228 <https://github.com/delano/familia/issues/228>`_.

- ``EncryptedData.from_json`` and ``validate!`` now filter unknown keys from
  parsed envelopes before instantiation. This prevents ``ArgumentError`` when
  reading envelopes written by future versions that include additional fields
  (e.g. ``encoding``, ``compression``).

AI Assistance
-------------

- Claude implemented the Phase 1 defensive read strategy, added the ``encoding``
  field to ``EncryptedData`` with nil default and ``to_h.compact`` for clean
  serialization, and wrote 22 test cases covering encoding round-trips, legacy
  envelope backward compatibility, unknown key filtering, and edge cases (nil
  input, bogus encoding names, binary ASCII-8BIT content).
  PR `#230 <https://github.com/delano/familia/pull/230>`_.

.. _changelog-2.3.1:

2.3.1 — 2026-03-06
==================

Fixed
-----

- Objects loaded from Redis via ``load``, ``find``, ``find_by_id``, ``find_by_dbkey``,
  and ``load_multi`` no longer appear dirty. The ``instantiate_from_hash`` factory
  now calls ``clear_dirty!`` after field assignment, matching the behavior of
  ``initialize`` and ``refresh!``. Previously, every loaded object had all fields
  marked dirty, causing false ``warn_if_dirty!`` warnings on subsequent collection
  writes. Fixes `#225 <https://github.com/delano/familia/issues/225>`_.

- Added ``warn_if_dirty!`` to 14 secondary collection mutation methods that were
  missing the write-order check: ``remove_element``, ``pop``, ``move`` (UnsortedSet);
  ``remove_element``, ``remrangebyrank``, ``remrangebyscore`` (SortedSet); ``pop``,
  ``shift``, ``remove_element`` (ListKey); ``hsetnx``, ``remove_field``,
  ``update``/``merge!`` (HashKey); ``value=``, ``setnx`` (JsonStringKey). Counter and
  increment methods are intentionally excluded as they operate independently of the
  parent's scalar lifecycle.

- ``batch_update`` and ``batch_fast_write`` now update in-memory field values only
  after the MULTI/EXEC transaction succeeds. Previously, setters ran inside the
  transaction block, so a failed transaction could leave the object's in-memory
  state diverged from Redis.

AI Assistance
-------------

- Claude identified the one-line fix in ``instantiate_from_hash``, audited all
  collection mutation paths for missing ``warn_if_dirty!`` calls, and triaged
  the 29 candidates into tiers based on write-order risk. Also caught the
  transaction-safety issue in ``batch_update``/``batch_fast_write`` during the
  broader audit.

.. _changelog-2.3.0:

2.3.0 — 2026-02-26
==================

Added
-----

- ``touch_instances!`` and ``remove_from_instances!`` instance methods for
  explicit instances timeline management. ``touch_instances!`` is idempotent
  (ZADD updates the timestamp without duplicating).

- ``in_instances?(identifier)`` class method for O(log N) membership checks
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

- Participation audit reads actual collection contents (not the instances
  timeline) and repairs use TYPE introspection to dispatch the correct
  removal command per collection type.

Changed
-------

- ``find_by_dbkey`` and ``find_by_identifier`` are now read-only.
  They no longer call ``cleanup_stale_instance_entry`` as a side effect
  when a key is missing. Ghost cleanup is the explicit responsibility
  of the audit/repair layer or direct caller invocation.
  ``cleanup_stale_instance_entry`` is now a public class method.

- Fast writers (``field!``), ``batch_update``, ``batch_fast_write``,
  and ``save_fields`` now clear dirty tracking state after a successful
  database write. Note: this currently clears all dirty flags, even for
  fields that were not part of the partial write. This known limitation
  is documented in ``try/features/dirty_tracking_try.rb`` and will be
  addressed in a future release.

Fixed
-----

- ``commit_fields``, ``batch_update``, ``save_fields``, and fast writers now
  touch the ``instances`` sorted set via ``touch_instances!``.
  Previously, only ``save`` updated the timeline, leaving objects created
  through other write paths invisible to ``instances.to_a`` enumeration.

- Class-level ``destroy!`` now removes the identifier from the ``instances``
  sorted set, preventing ghost entries after deletion.

Documentation
-------------

- Added serialization encoding guide to CLAUDE.md showing how each DataType
  serializes values and what raw Redis output looks like per type.

AI Assistance
-------------

- Implementation, test authoring, and iterative debugging performed with
  Claude Opus 4.6 assistance across dirty tracking, write-order guards,
  TTL reporting, debug_fields, audit/repair infrastructure, and 211 test
  cases across 14 audit files.

.. _changelog-2.2.0:

2.2.0 — 2026-02-23
==================

Added
-----

- Introduced ``reference: true`` option for DataType collection declarations.
  Collections with this option store member identifiers raw instead of
  JSON-encoding them, resolving the semantic mismatch between field storage
  (type-preserving JSON) and collection member storage (identity references).

Fixed
-----

- Fixed serialization mismatch in ``instances`` sorted set where
  ``persist_to_storage`` passed a string identifier (JSON-encoded as
  ``"\"abc-123\""``), while direct calls passed Familia objects (stored raw as
  ``abc-123``). Now passes ``self`` to ``instances.add`` and declares
  ``reference: true`` on the collection, ensuring consistent storage.
  (`#215 <https://github.com/delano/familia/issues/215>`_)

- Fixed ``UnsortedSet#pop`` returning raw Redis strings instead of deserialized
  values.

- Fixed ``UnsortedSet#move`` passing raw values to Redis instead of serializing
  them.

- Fixed ``SortedSet#increment`` truncating scores to integer (``.to_i``) instead
  of preserving float precision (``.to_f``).

Documentation
-------------

- Added collection member serialization guide to ``docs/guides/field-system.md``
  explaining the distinction between field serialization (JSON for type
  preservation) and collection member serialization (raw identifiers for
  reference collections).

AI Assistance
-------------

- Claude assisted with systematic audit of all ``.add()`` call sites and
  collection declarations across the codebase, identifying the root cause of the
  serialization mismatch and the three additional DataType method bugs discovered
  during the audit.

.. _changelog-2.1.1:

2.1.1 — 2026-02-02
==================

Added
-----

- Added ``serialization_consistency_try.rb`` regression tests verifying that
  object-based lookups work consistently across relationships module and direct
  DataType access for sorted sets, unsorted sets, and lists.

Fixed
-----

- Fixed serialization mismatch in relationships module where extracting
  ``.identifier`` before passing to DataType methods caused cross-path lookup
  failures. Items added via relationships couldn't be found via direct DataType
  access because ``serialize_value(object)`` extracts raw identifiers while
  ``serialize_value(string)`` JSON-encodes them. Now passes Familia objects
  directly to DataType methods. (`#212 <https://github.com/delano/familia/issues/212>`_)

Documentation
-------------

- Documented known limitation: string identifier lookups get JSON-encoded by
  design. Always use Familia objects instead of raw string identifiers for
  DataType operations like ``member?()``, ``score()``, and ``remove()``.

AI Assistance
-------------

- Claude assisted with root cause analysis of the serialization mismatch,
  identifying the 7 occurrences in ``collection_operations.rb`` where
  ``.identifier`` extraction needed to be removed, and writing comprehensive
  regression tests covering all three collection types.

.. _changelog-2.1.0:

2.1.0 — 2026-02-01
==================

Added
-----

- Redis-native migration system with three patterns: Base (abstract foundation),
  Model (record-by-record iteration via SCAN), and Pipeline (bulk updates with
  Redis pipelining). Includes dependency resolution using topological sort,
  dry-run mode, CLI support, and comprehensive Rake tasks.

- Migration registry for tracking applied migrations in Redis with rollback
  support and schema drift detection.

- Lua script framework with atomic operations: rename_field, copy_field,
  delete_field, rename_key_preserve_ttl, and backup_and_modify_field.

- Optional JSON Schema validation for Horreum models via ``feature :schema_validation``
  with centralized SchemaRegistry supporting convention-based and explicit schema
  discovery using the json_schemer gem.

- V1 to V2 serialization migration example at ``examples/migrations/v1_to_v2_serialization_migration.rb``
  demonstrating how to upgrade Horreum objects from v1.x format (selective serialization
  with type information loss) to v2.0 format (universal JSON encoding with type preservation).
  Includes type detection heuristics, field type declarations, and batch processing.

Documentation
-------------

- Added comprehensive migration writing guide at ``docs/guides/writing-migrations.md``
  covering all three migration patterns, CLI usage, dependencies, and best practices.

AI Assistance
-------------

- Claude Code assisted with test coverage analysis, identifying gaps in Model and
  Pipeline test coverage. Implemented 67 new tests covering CLI entry points,
  circular dependency detection, and comprehensive Model/Pipeline scenarios.

- Claude Code identified and fixed a bug where schema validation hooks were never
  triggered in Model migrations, and optimized N+1 query patterns in Registry and
  Runner classes.

.. _changelog-2.0.0:

2.0.0 — 2026-01-19
==================

Familia 2.0.0 represents a complete rewrite of the library with 26 pre-release
iterations incorporating community feedback and production testing.

Added
-----

- **Modular Feature System**: Autoloading features with ancestry chain traversal
  (``feature :expiration``, ``feature :relationships``, etc.)
- **Unified Relationships API**: ``participates_in`` replaces ``tracked_in``/``member_of``
  with bidirectional reverse lookups (``_instances`` suffix methods)
- **Type-Safe Serialization**: JSON encoding preserves Integer, Boolean, Float,
  Hash, Array types across Redis boundary
- **Performance Optimizations**: Pipelined bulk loading (``load_multi``),
  optional EXISTS check (``check_exists: false``), OJ JSON for 2-5× faster operations
- **Security Features**: VerifiableIdentifier with HMAC signatures,
  ExternalIdentifier with format flexibility, encrypted fields with key rotation
- **Thread Safety**: Mutex initialization fixes, 56-test thread safety suite
- **Instrumentation**: ``Familia.on_command``, ``Familia.on_pipeline``,
  ``Familia.on_lifecycle`` hooks for monitoring

Changed
-------

- **BREAKING**: DataType class renaming to avoid Ruby namespace conflicts
  (``Familia::String`` → ``Familia::StringKey``, etc.)
- **BREAKING**: Removed ``dump_method``/``load_method`` - JSON serialization is now standard
- **BREAKING**: Indexing API renamed (``class_indexed_by`` → ``unique_index``,
  ``indexed_by`` → ``multi_index``)

Documentation
-------------

- Archived 11 pre-release migration guides to ``docs/.archive/``
- Enhanced ``api-technical.md`` with bulk loading, EXISTS optimization,
  per-class feature registration, and index rebuilding documentation
- Updated version references and fixed broken anchor links throughout docs

AI Assistance
-------------

- Claude Opus 4.5 coordinated 11 parallel code-explorer agents to evaluate
  migration docs, identifying unique content to preserve before archiving.
  Assisted with release statistics gathering and documentation consolidation.

.. _changelog-2.0.0.pre26:

2.0.0.pre26 — 2026-01-19
========================

Fixed
-----

- Fixed relationship reverse lookup methods failing when a class declares an explicit
  ``prefix`` that differs from its computed ``config_name``. For example, a class with
  ``prefix :customdomain`` (no underscore) but ``config_name`` returning ``"custom_domain"``
  (with underscore) now correctly finds related instances. PR #207

AI Assistance
-------------

- Claude Opus 4.5 assisted with root cause analysis, coordinating multiple agents to
  explore the codebase, implementing the fix across 5 locations, and writing comprehensive
  test coverage (53 test cases) for various prefix/config_name scenarios.

.. _changelog-2.0.0.pre25:

2.0.0.pre25 — 2026-01-08
========================

Added
-----

- Class-level multi-value indexing with ``multi_index :field, :index_name`` (``within: :class`` is now the default). Creates class methods like ``Model.find_all_by_field(value)`` and ``Model.sample_from_field(value, count)`` for grouping objects by field values at the class level.

- New ``JsonStringKey`` DataType for type-preserving string storage. Unlike
  ``StringKey`` which uses raw strings (for INCR/DECR support), ``JsonStringKey``
  uses JSON serialization to preserve Ruby types (Integer, Float, Boolean, Hash,
  Array) across the Redis storage boundary. Registered as ``:json_string`` and
  ``:json_stringkey``, enabling DSL methods like ``json_string :metadata`` and
  ``class_json_string :last_synced_at``.

Changed
-------

- ``multi_index`` now defaults to ``within: :class`` instead of requiring a scope class. Existing instance-scoped indexes (``within: SomeClass``) continue to work unchanged.

Removed
-------

- **BREAKING**: Removed ``dump_method`` and ``load_method`` configuration options
  from ``Familia::Base``, ``Familia::Horreum``, and ``Familia::DataType``. JSON
  serialization via ``to_json``/``from_json`` is now hard-coded for consistency
  and type safety. Custom serialization methods are no longer supported.

AI Assistance
-------------

- Claude Opus 4.5 assisted with design, implementation, and testing of serialization consistency, the JsonStringKey feature, and multi_index :class mode.
- Gemini 3 Flash assisted with editing and trimming this section.


.. _changelog-2.0.0.pre24:

2.0.0.pre24 — 2026-01-07
========================

Added
-----

- Add comprehensive test coverage for ``find_by_dbkey`` race condition and lazy cleanup
  scenarios in ``try/edge_cases/find_by_dbkey_race_condition_try.rb`` (16 new tests).
  Tests cover empty hash handling, lazy cleanup, TTL expiration, count consistency,
  and concurrent access patterns.

Fixed
-----

- Fix race condition in ``find_by_dbkey`` where keys expiring between EXISTS and HGETALL
  could create objects with nil identifiers, causing ``NoIdentifier`` errors on subsequent
  operations like ``destroy!``. Now always checks for empty hash results regardless of
  ``check_exists`` parameter value.

- Add lazy cleanup of stale ``instances`` sorted set entries when ``find_by_dbkey`` detects
  a non-existent key (via EXISTS check) or an expired key (via empty HGETALL result). This
  prevents phantom instance counts from accumulating when objects expire via TTL without
  explicit ``destroy!`` calls. The cleanup is performed opportunistically during load
  attempts, requiring no background jobs or Redis keyspace notifications.

AI Assistance
-------------

- Claude helped verify the race condition analysis through multi-agent investigation
  (Explore, Code Explorer, QA Engineer agents) and implemented the fix with lazy cleanup
  and comprehensive test coverage.

.. _changelog-2.0.0.pre23:

2.0.0.pre23 — 2025-12-22
========================

Added
-----

- Add ``:through`` option to ``participates_in`` for join model support.
  Enables storing additional attributes (role, permissions, metadata) on
  participation relationships via an intermediate model. The through model
  uses deterministic keys and supports idempotent operations - adding an
  existing participant updates rather than duplicates.

Security
--------

- Add validation for through model attributes to prevent arbitrary method
  invocation. Only fields defined on the through model schema can be set
  via the ``through_attrs`` parameter.

Documentation
-------------

- Add YARD documentation for the ``:through`` parameter on both
  ``participates_in`` and ``class_participates_in`` methods.

AI Assistance
-------------

- Implementation design and code review assistance provided by Claude.
  Security hardening for attribute validation added based on Qodo review.

.. _changelog-2.0.0.pre22:

2.0.0.pre22 — 2025-12-03
========================

- **ExternalIdentifier Format Flexibility**: The `external_identifier` feature now supports customizable format templates via the `format` option (e.g., `format: 'cust_%{id}'` or `format: 'api-%{id}'`). Default format remains `'ext_%{id}'`. Provides complete flexibility for various ID formatting needs including different prefixes, separators, URL paths, or no prefix at all.

- **Participation Relationships with Symbol/String Target Classes**: Fixed four bugs that occurred when calling `participates_in` with Symbol/String target class instead of Class object. Issues included NoMethodError during relationship definition (private method call), failures in `current_participations` (undefined `familia_name`), errors in `target_class_config_name` (undefined `config_name`), and confusing error messages for load order issues. All now properly resolve using `Familia.resolve_class` API with clear error messages for common issues.

- **Pipelined Bulk Loading Methods**: New `load_multi` and `load_multi_by_keys` methods enable efficient bulk object loading using Redis pipelining, reducing network round trips from N×2 commands to a single batch (up to 2× performance improvement). Methods maintain nil-return contract for missing objects and preserve input order.

- **Optional EXISTS Check Optimization**: The `find_by_dbkey` and `find_by_identifier` methods now accept `check_exists:` parameter (default: `true`) to optionally skip EXISTS check, reducing Redis commands from 2 to 1 per object. Maintains backwards compatibility and same nil-return behavior.

- **Parameter Consistency**: The `suffix` parameter in `find_by_identifier` is now a keyword parameter (was optional positional) for consistency with `check_exists`, following Ruby conventions.

Added
-----

- Bidirectional reverse collection methods for ``participates_in`` with ``_instances`` suffix (e.g., ``user.project_team_instances``, ``user.project_team_ids``). Supports union behavior for multiple collections and custom naming via ``as:`` parameter. Closes #179.

Changed
-------

- All Ruby files now include consistent headers with ``frozen_string_literal: true`` pragma for improved performance and memory efficiency. Headers follow the format: filename comment, blank comment line, frozen string literal pragma. Executable scripts properly place shebang first.

- Standardized DataType serialization to use JSON encoding for type preservation, matching Horreum field behavior. All primitive values (Integer, Boolean, String, Float, Hash, Array, nil) are now consistently serialized through JSON, ensuring types are preserved across the Redis storage boundary. Familia object references continue to use identifier extraction. Issue #190.

Fixed
-----

- Fixed critical race condition in mutex initialization for connection chain lazy loading. The mutex itself was being lazily initialized with ``||=``, which is not atomic and could result in multiple threads creating different mutex instances, defeating synchronization. Changed to eager initialization via ``Connection.included`` hook. (`lib/familia/horreum/connection.rb`)

- Fixed critical race condition in mutex initialization for logger lazy loading. Similar to connection chain issue, the logger mutex was lazily initialized with ``||=``. Changed to eager initialization at module definition time. (`lib/familia/logging.rb`)

- Fixed logger assignment atomicity issue where ``Familia.logger=`` set ``DatabaseLogger.logger`` outside the mutex synchronization block, potentially causing ``Familia.logger`` and ``DatabaseLogger.logger`` to be temporarily out of sync during concurrent access. Moved ``DatabaseLogger.logger`` assignment inside the synchronization block. (`lib/familia/logging.rb`)

- Added explicit return statement to ``Familia.logger`` method for robustness against future refactoring. (`lib/familia/logging.rb`)

AI Assistance
-------------

- Claude Code (Opus 4, Sonnet 4.5): Implementation of bidirectional participation relationships, external identifier format flexibility, bulk loading optimization with pipelining, race condition fixes in mutex initialization, frozen string literal pragma automation (308 files), and DataType serialization standardization. Comprehensive test coverage and documentation throughout.

.. _changelog-2.0.0.pre21:

2.0.0.pre21 — 2025-10-21
========================

Added
-----

- Pipeline Routing Investigation: Created 7 diagnostic testcases in ``try/investigation/pipeline_routing/`` to investigate suspected middleware routing issue. Investigation revealed single-command pipelines don't have ' | ' separator (expected Array#join behavior), confirming no routing bug exists. Full analysis documented in ``CONCLUSION.md``.

Changed
-------

- **BREAKING**: Duration measurements now use integer microseconds instead of milliseconds. Instrumentation hooks and logging output have changed format:

  - ``Familia.on_command`` receives ``duration`` in microseconds (was ``duration_ms`` in milliseconds)
  - ``Familia.on_pipeline`` receives ``duration`` in microseconds (was ``duration_ms`` in milliseconds)
  - ``Familia.on_lifecycle`` uses ``duration`` key in microseconds (was ``duration_ms`` in milliseconds)
  - Log messages show ``duration=1234`` (microseconds) instead of ``duration_ms=1.23`` (milliseconds)

- Migration: Convert to milliseconds when needed: ``duration / 1000.0``

Fixed
-----

- Connection Chain Race Condition: Fixed race condition in connection chain initialization where concurrent calls could create multiple instances. Added thread-safe protection to ensure proper singleton behavior.

- Thread Safety Test Suite: Corrected test assertions to properly verify thread safety invariants.


AI Assistance
-------------

- Claude Code assisted with analyzing test failures, identifying and fixing the connection chain race condition with Mutex protection, correcting test assertions to verify proper thread safety invariants, and creating diagnostic testcases to investigate pipeline routing behavior.



.. _changelog-2.0.0.pre20:

2.0.0.pre20 — 2025-10-20
========================

Added
-----

- **Instrumentation Hooks**: New ``Familia::Instrumentation`` module provides hooks for Redis commands, pipeline operations, lifecycle events, and errors. Applications can now register callbacks for audit trails and performance monitoring.

- **DatabaseLogger Structured Mode**: Added ``DatabaseLogger.structured_logging`` mode that outputs Redis commands with structured key=value context instead of formatted string output.

- **DatabaseLogger Sampling**: Added ``DatabaseLogger.sample_rate`` for controlling log volume in high-traffic scenarios. Set to 0.1 for 10% sampling, 0.01 for 1% sampling, or nil to disable. Command capture for testing remains unaffected.

- **Lifecycle Logging**: Horreum initialize, save, and destroy operations now log with timing and structured context when ``FAMILIA_DEBUG`` is enabled.

- **Operational Logging**: TTL operations and serialization errors now include structured context for better debugging.

Changed
-------

- Refactored ``save`` and ``save_if_not_exists!`` to use shared helper methods (``prepare_for_save`` and ``persist_to_storage``) to eliminate code duplication and ensure consistency. Both methods now follow the same preparation and persistence logic, differing only in their concurrency control patterns (simple transaction vs. optimistic locking with WATCH).

- **Structured Logging**: Replaced internal logging methods (``Familia.ld``, ``Familia.le``) with structured logging methods (``Familia.debug``, ``Familia.info``, ``Familia.error``) that support keyword context for operational observability.

Removed
-------

- **Internal Methods**: Removed ``Familia.ld`` and ``Familia.le`` internal logging methods. These were never part of the public API.

Fixed
-----

- Fixed ``save_if_not_exists!`` to perform the same operations as ``save`` when creating new objects. Previously, ``save_if_not_exists!`` omitted timestamp updates (``created``/``updated``), unique index validation (``guard_unique_indexes!``), and adding to the instances collection. Now both methods produce identical results when saving a new object, with ``save_if_not_exists`` only differing in its conditional existence check.

- Fixed ``save_if_not_exists!`` return value to correctly return ``true`` when successfully saving new objects. Previously returned ``false`` despite successful persistence due to incorrect handling of transaction result.

Documentation
-------------

- Streamlined inline documentation for ``save``, ``save_if_not_exists!``, and ``save_if_not_exists`` methods to be more concise, internally consistent, and non-redundant. Each method's documentation now stands on its own with clear, focused descriptions.

AI Assistance
-------------

- Claude Code identified the inconsistencies between ``save`` and ``save_if_not_exists!`` methods, implemented the fixes, refactored both methods to extract shared logic into private helper methods (``prepare_for_save`` and ``persist_to_storage``), and updated the documentation to be more concise and internally consistent.



This implementation was completed with significant AI assistance from Claude (Anthropic), including:

- Architecture design for the instrumentation hook system
- Implementation of structured logging methods with backward-compatible signatures
- Integration of hooks into DatabaseLogger middleware
- Bulk replacement of 51 logging method calls across 21 files
- Comprehensive code review and bug fixes (RedisClient::Config object vs hash handling)
- Documentation and changelog creation

The AI provided discussion, rubber ducking, code generation, testing strategy, and documentation throughout the implementation process.

Developer Notes
---------------

This is a clean break for v2.0 with no deprecation warnings, as the removed methods were internal-only. Applications using the public API are unaffected.

**Migration**: No action required for external users. Internal development references to ``Familia.ld`` should use ``Familia.debug``, and ``Familia.le`` should use ``Familia.error``.

**New Capabilities**: Applications can now register instrumentation hooks for operational observability:

.. code-block:: ruby

   # Enable structured logging with 10% sampling for production
   Familia.logger = Rails.logger
   DatabaseLogger.structured_logging = true
   DatabaseLogger.sample_rate = 0.1  # Log 10% of commands

   # Register hooks for audit trails
   Familia.on_command do |cmd, duration_ms, context|
     AuditLog.create!(
       event: 'redis_command',
       command: cmd,
       duration_ms: duration_ms,
       user_id: RequestContext.current_user_id
     )
   end

   Familia.on_lifecycle do |event, instance, context|
     case event
     when :save
       AuditLog.create!(event: 'object_saved', object_id: instance.identifier)
     when :destroy
       AuditLog.create!(event: 'object_destroyed', object_id: instance.identifier)
     end
   end

.. _changelog-2.0.0.pre19:

2.0.0.pre19 — 2025-10-13
========================

Added
-----

-  **DataType Transaction and Pipeline Support** - DataType objects can now initiate transactions and pipelines independently, enabling atomic operations and batch command execution. `PR #159 <https://github.com/familia/familia/pull/159>`_

   * ``transaction`` and ``pipelined`` methods for all DataType classes
   * Connection chain pattern with ``ParentDelegationHandler`` and ``StandaloneConnectionHandler``
   * Enhanced ``direct_access`` method with automatic context detection
   * Shared ``Familia::Connection::Behavior`` module for common functionality

-  **Automatic Unique Index Validation** - Instance-scoped unique indexes now validate automatically in ``add_to_*`` methods, with transaction detection to prevent ``save()`` calls within MULTI/EXEC blocks

Changed
-------

-  **Connection Architecture** - Refactored to share ``Familia::Connection::Behavior`` between Horreum and DataType, with cleaner URI construction for logical databases

-  **Indexing Terminology** - Renamed internal ``target_class`` to ``scope_class`` throughout to clarify semantic role. Added explicit ``:within`` field to IndexingRelationship for clearer instance-scoped index handling

Fixed
-----

-  URI formatting for DataType objects with logical database settings
-  Transaction detection and validation flow for unique index operations

Documentation
-------------

-  Enhanced ``save()`` method documentation with transaction restrictions
-  Updated indexing and relationship cheatsheets with improved terminology
-  Added comprehensive test coverage (48 new tests) for transactions, pipelines, and validation

AI Assistance
-------------

This release was implemented with assistance from Claude (Anthropic) for architectural design, test coverage, and systematic refactoring of terminology across the codebase.


.. _changelog-2.0.0.pre18:

2.0.0.pre18 — 2025-10-05
========================

Added
-----

- Added ``Familia.reconnect!`` method to refresh connection pools with current middleware configuration. This solves issues in test suites where middleware (like DatabaseLogger) is enabled after connection pools are created. The method clears the connection chain, increments the middleware version, and clears fiber-local connections, ensuring new connections include the latest middleware. See ``lib/familia/connection/middleware.rb:81-117``.

Changed
-------

- **BREAKING**: Implemented type-preserving JSON serialization for Horreum field values. Non-string values (Integer, Boolean, Float, nil, Hash, Array) are JSON-encoded for storage and JSON-decoded on retrieval. **Strings are stored as-is without JSON encoding** to avoid double-quoting and maintain Redis baseline simplicity. Type preservation is achieved through smart deserialization: values that parse as JSON restore to their original types, otherwise remain as strings.

- **BREAKING**: Changed default Hash key format from symbols to strings throughout the codebase (``symbolize: false`` default). This eliminates ambiguity with HTTP request parameters and IndifferentHash-style implementations, providing strict adherence to JSON parsing rules and avoiding key duplication issues.

- **BREAKING**: Fixed ``initialize_with_keyword_args`` to properly handle ``false`` and ``0`` values during object initialization. Previously, falsy values were incorrectly skipped due to truthiness checks. Now uses explicit nil checking with ``fetch`` to preserve all non-nil values including ``false`` and ``0``.

- **String serialization now uses JSON encoding**: All string values are JSON-encoded during storage (wrapped in quotes) for consistent type preservation. The lenient deserializer handles both new JSON-encoded strings and legacy plain strings automatically. PR #152

Removed
-------

- **BREAKING**: Removed ``dump_method`` and ``load_method`` configuration options from ``Familia::Base`` and ``Familia::Horreum::Definition``. JSON serialization is now hard-coded for consistency and type safety. Custom serialization methods are no longer supported.

Fixed
-----

- Fixed type coercion bugs where Integer fields (e.g., ``age: 35``) became Strings (``"35"``) and Boolean fields (e.g., ``active: true``) became Strings (``"true"``) after database round-trips. All primitive types now maintain their original types through ``find_by_dbkey``, ``refresh!``, and ``batch_update`` operations.

- Fixed ``deserialize_value`` to return all JSON-parsed types instead of filtering to Hash/Array only. This enables proper deserialization of primitive types (Integer, Boolean, Float, String) from Redis storage.

- Added JSON deserialization in ``find_by_dbkey`` using existing ``initialize_with_keyword_args_deserialize_value`` helper method to maintain DRY principles and ensure loaded objects receive properly typed field values rather than raw Redis strings.

- Optimized serialization to avoid double-encoding strings - strings stored directly in Redis as-is, only non-string types use JSON encoding. This reduces storage overhead and maintains Redis's string baseline semantics.

- Fixed encrypted fields with ``category: :encrypted`` appearing in ``to_h()`` output. These fields now correctly set ``loggable: false`` to prevent accidental exposure in logs, APIs, or external interfaces. PR #152

- Fixed middleware registration to only set ``@middleware_registered`` flag when middleware is actually enabled and registered. Previously, calling ``create_dbclient`` before enabling middleware would set the flag to ``true`` without registering anything, preventing later middleware enablement from working. The fix ensures ``register_middleware_once`` only sets the flag after successful registration. See ``lib/familia/connection/middleware.rb:124-146``.

Security
--------

- Encrypted fields defined via ``field :name, category: :encrypted`` now properly excluded from ``to_h()`` serialization, matching the security behavior of ``encrypted_field``. PR #152

Documentation
-------------

- Added comprehensive type preservation test suite (``try/unit/horreum/json_type_preservation_try.rb``) with 30 test cases covering Integer, Boolean, String, Float, Hash, Array, nested structures, nil handling, empty strings, zero values, round-trip consistency, ``batch_update``, and ``refresh!`` operations.

AI Assistance
-------------

- Claude Code (claude-sonnet-4-5) provided implementation guidance, identified the ``initialize_with_keyword_args`` falsy value bug, wrote test coverage, and coordinated multi-file changes across serialization, management, and base modules.

- Issue analysis, implementation guidance, test verification, and documentation for JSON serialization changes and encrypted field security fix.

- Claude Code (Sonnet 4.5) provided architecture analysis, implementation design, and identified critical issues through the second-opinion agent. Key contributions included recommending the simplified approach without pool shutdown lifecycle management, identifying the race condition risk in clearing ``@middleware_registered``, and suggesting the use of natural pool aging instead of explicit shutdown.

.. _changelog-2.0.0.pre17:

2.0.0.pre17 — 2025-10-03
========================

Added
-----

- **SortedSet#add** - Full ZADD option support (NX, XX, GT, LT, CH) for atomic conditional operations and accurate change tracking. Closes #135

Fixed
-----

- Restored objid provenance tracking when loading objects from Redis, enabling dependent features to derive external identifiers. PR #131

AI Assistance
-------------

- Claude (Anthropic) assisted with objid generator inference implementation and ZADD option validation design.

.. _changelog-2.0.0.pre16:

2.0.0.pre16 — 2025-09-30
========================

Added
-----

- **Instance-scoped unique indexes** via ``unique_index`` with ``within:`` parameter for per-scope unique lookups. Issue #128

Changed
-------

- **BREAKING**: Consolidated relationships API - replaced ``tracked_in`` and ``member_of`` with unified ``participates_in`` method. PR #110

- **BREAKING**: Renamed indexing API methods for clarity. Issue #128
  - ``class_indexed_by`` → ``unique_index``
  - ``indexed_by`` → ``multi_index``
  - Changed ``multi_index`` to use ``UnsortedSet`` instead of ``SortedSet``

- **DataType class renaming** to avoid Ruby namespace conflicts: ``Familia::String`` → ``Familia::StringKey``, ``Familia::List`` → ``Familia::ListKey``, etc., with dual registration for compatibility

Documentation
-------------

- Updated indexing and participation module documentation with comprehensive examples and design philosophy

AI Assistance
-------------

- Claude (Anthropic) assisted with relationship API consolidation, DataType renaming, and indexing API refactoring.

.. _changelog-2.0.0.pre14:

2.0.0.pre14 — 2025-09-08
========================

Changed
-------

- **BREAKING**: Renamed ``TimeUtils`` to ``TimeLiterals`` to better reflect module purpose. PR #100

Fixed
-----

- **CRITICAL**: Fixed Redis connection persistence for standalone DataType objects. PR #107
- Fixed ExternalIdentifier HashKey cleanup using correct ``remove_field()`` method. PR #100

AI Assistance
-------------

- Claude (Anthropic) and Gemini assisted with TimeLiterals refactoring and ExternalIdentifier fixes.

.. _changelog-2.0.0.pre13:

2.0.0.pre13 — 2025-09-07
========================

Added
-----

- **Feature Autoloading System** - Features automatically discover and load extension files from project directories using conventional patterns. PR #97

- **Month calculations** - Added ``PER_MONTH`` constant and month conversion methods to TimeLiterals refinement. Issue #94

Changed
-------

- **Performance** - Replaced stdlib JSON with OJ gem for 2-5x faster operations. PR #97
- Refactored time/numeric extensions from global monkey patches to Ruby refinements
- Enhanced encryption serialization safety with improved ConcealedString handling

Fixed
-----

- Fixed ``months_old`` and ``years_old`` methods returning raw seconds instead of proper units. Issue #94
- Fixed byte conversion boundary logic (``size >= 1024`` instead of ``size > 1024``)
- Fixed calendar consistency where ``12.months != 1.year`` by using Gregorian year

Security
--------

- Improved concealed value protection during JSON serialization across all OJ modes. PR #97

Documentation
-------------

- Added Feature System Autoloading guide with conventions and usage examples
- Enhanced YARD documentation for autoloading modules

AI Assistance
-------------

- Claude (Anthropic) assisted with refinement refactoring, autoloading system design, and OJ integration.

2.0.0.pre12 — 2025-09-04
========================

Added
~~~~~

-  Added the ``Familia::VerifiableIdentifier`` module to create and
   verify identifiers with an embedded HMAC signature. This allows an
   application to stateless-ly confirm that an identifier was generated
   by itself, preventing forged IDs from malicious sources.

-  **Scoped VerifiableIdentifier**: Added ``scope`` parameter to
   ``generate_verifiable_id()`` and ``verified_identifier?()`` methods,
   enabling cryptographically isolated identifier namespaces for
   multi-tenant, multi-domain, or multi-environment applications while
   maintaining full backward compatibility with existing code.

Changed
~~~~~~~

-  ObjectIdentifier feature now tracks which generator (uuid_v7,
   uuid_v4, hex, or custom) was used for each objid to provide
   provenance information for security-sensitive operations.

-  Updated external identifier derivation to normalize objid format
   based on the known generator type, eliminating format ambiguity
   between UUID and hex formats.

-  Refactored identifier generation methods for clarity and consistency.
   Method ``generate_objid`` is now ``generate_object_identifier``, and
   ``generate_external_identifier`` is now
   ``derive_external_identifier`` to reflect its deterministic nature.

Removed
~~~~~~~

-  Removed the ``generate_extid`` class method, which was less secure
   than the instance-level derivation logic.

Security
~~~~~~~~

-  Hardened external identifier derivation with provenance validation.
   ExternalIdentifier now validates that objid values come from the
   ObjectIdentifier feature before deriving external identifiers,
   preventing derivation from potentially malicious or unvalidated objid
   values while maintaining deterministic behavior for legitimate use
   cases.

-  Improved the security of external identifiers (``extid``) by using
   the internal object identifier (``objid``) as a seed for a new random
   value, rather than deriving the ``extid`` directly. This prevents
   potential information leakage from the internal ``objid``.

Documentation
~~~~~~~~~~~~~

-  Added detailed YARD documentation for ``VerifiableIdentifier``,
   explaining how to securely generate and manage the required
   ``VERIFIABLE_ID_HMAC_SECRET`` key.

AI Assistance
~~~~~~~~~~~~~

-  Security analysis of external identifier derivation and hardened
   design approach was discussed and developed with AI assistance,
   including provenance tracking, validation logic, format
   normalization, and comprehensive test updates.

-  Implementation of scoped verifiable identifiers was developed with AI
   assistance to ensure cryptographic security properties and
   comprehensive test coverage.

2.0.0.pre11 - 2025-09-03
======================

.. _added-1:

Added
~~~~~

-  **Enhanced Feature System**: Introduced a hierarchical feature system
   with ancestry chain traversal for model-specific feature
   registration. This enables better organization, standardized naming,
   and automatic loading of project-specific features via the new
   ``Familia::Features::Autoloader`` module.
-  **Improved SafeDump DSL**: Replaced the internal
   ``@safe_dump_fields`` implementation with a cleaner, more robust DSL
   using ``safe_dump_field`` and ``safe_dump_fields`` methods.
-  Added ``generate_short_id`` and ``shorten_securely`` utility methods
   for creating short, secure identifiers, adapted from
   ``OT::Utils::SecureNumbers``.
-  For a detailed guide on migrating to the new feature system, see
   ``docs/migration/v2.0.0-pre11.md``.

.. _changed-1:

Changed
~~~~~~~

-  External identifier now raises an ``ExternalIdentifierError`` if the
   model does not have an objid field. Previously: returned nil. In
   practice this should never happen, since the external_identifier
   feature declares its dependency on object_identifier.
-  Moved lib/familia/encryption_request_cache.rb to
   lib/familia/encryption/request_cache.rb for consistency.
-  **Simplified ObjectIdentifier Feature Implementation**: Consolidated
   the ObjectIdentifier feature from two files (~190 lines) to a single
   file (~140 lines) by moving the ObjectIdentifierFieldType class
   inline. This reduces complexity while maintaining all existing
   functionality including lazy generation, data integrity preservation,
   and multiple generator strategies.
-  **Renamed Identifier Features to Singular Form**: Renamed
   ``object_identifier`` → ``object_identifier`` and
   ``external_identifier`` → ``external_identifier`` for more accurate
   naming. Added full-length aliases
   (``object_identifier``/``external_identifier``) alongside the short
   forms (``objid``/``extid``) for clarity when needed.
-  **Simplified ExternalIdentifier Feature Implementation**:
   Consolidated the ExternalIdentifier feature from two files (~240
   lines) to a single file (~120 lines) by moving the
   ExternalIdentifierFieldType class inline, following the same pattern
   as ObjectIdentifier.

Fixed
~~~~~

-  Fixed external identifier generation returning all zeros for
   UUID-based objids. The ``shorten_to_external_id`` method now
   correctly handles both 256-bit secure identifiers and 128-bit UUIDs
   by detecting input length and applying appropriate bit truncation
   only when needed.

.. _security-1:

Security
~~~~~~~~

-  Improved input validation in ``shorten_to_external_id`` method by
   replacing insecure character count checking with proper bit length
   calculation and explicit validation. Invalid inputs now raise clear
   error messages instead of being silently processed incorrectly.

2.0.0-pre10 - 2025-09-02
======================

.. _added-2:

Added
~~~~~

-  The ``Familia::Horreum`` initializer now supports creating an object
   directly from its identifier by passing a single argument (e.g.,
   ``Customer.new(customer_id)``). This provides a more convenient and
   intuitive way to instantiate objects from lookups.

-  Automatic indexing and class-level tracking on ``save()`` operations,
   eliminating the need for manual index updates.

-  Enhanced collection syntax supports the Ruby-idiomatic ``<<``
   operator for more natural relationship management.

.. _changed-2:

Changed
~~~~~~~

-  The ``member_of`` relationship is now bidirectional. A single call to
   ``member.add_to_owner_collection(owner)`` is sufficient to establish
   the relationship, removing the need for a second, redundant call on
   the owner object. This fixes bugs where members could be added to
   collections twice.

-  **BREAKING**: Refactored Familia Relationships API to remove “global”
   terminology and simplify method generation. (Closes #86)

-  Split ``generate_indexing_instance_methods`` into focused
   ``generate_direct_index_methods`` and
   ``generate_relationship_index_methods`` for better separation between
   direct class-level and relationship-based indexing.

-  Simplified method generation by removing complex global vs parent
   conditionals.

-  All indexes are now stored at the class level for consistency.

.. _fixed-1:

Fixed
~~~~~

-  Fixed a bug in the ``class_indexed_by`` feature where finder methods
   (e.g., ``find_by_email``) would fail to correctly instantiate objects
   from the index, returning partially-formed objects.

-  Refactored connection handling to properly cache and reuse Valkey/Redis
   connections. This eliminates repetitive “Overriding existing
   connection” warnings and improves performance.

-  Method generation now works consistently for both
   ``class_indexed_by`` and ``indexed_by`` with a ``parent:``.

-  Resolved metadata storage issues for dynamically created classes.

-  Improved error handling for nil class names in tracking
   relationships.

.. _documentation-1:

Documentation
~~~~~~~~~~~~~

-  Updated the ``examples/relationships_basic.rb`` script to reflect the
   improved, bidirectional ``member_of`` API and to ensure a clean
   database state for each run.

.. _ai-assistance-1:

AI Assistance
~~~~~~~~~~~~~

-  This refactoring was implemented with Claude Code assistance,
   including comprehensive test updates and API modernization.

2.0.0-pre9 - 2025-09-02
======================

.. _added-3:

Added
~~~~~

-  Added ``class_tracked_in`` method for global tracking relationships
   following Horreum’s established ``class_`` prefix convention
-  Added ``class_indexed_by`` method for global index relationships with
   consistent API design

.. _changed-3:

Changed
~~~~~~~

-  **BREAKING**: ``tracked_in :global, collection`` syntax now raises
   ArgumentError - use ``class_tracked_in collection`` instead
-  **BREAKING**: ``indexed_by field, index, target: :global`` syntax
   replaced with ``class_indexed_by field, index``
-  **BREAKING**: ``indexed_by field, index, target: SomeClass`` syntax
   replaced with ``indexed_by field, index, parent: SomeClass``
-  Relationships API now provides consistent parameter naming across all
   relationship types

.. _documentation-2:

Documentation
~~~~~~~~~~~~~

-  Updated Relationships Guide with new API syntax and migration
   examples
-  Updated relationships method documentation with new method signatures
-  Updated basic relationships example to demonstrate new API patterns
-  Added tryouts test coverage in
   try/features/relationships/relationships_api_changes_try.rb

2.0.0-pre8 - 2025-09-01
======================

.. _added-4:

Added
~~~~~

-  Implemented Scriv-based changelog system for sustainable
   documentation
-  Added fragment-based workflow for tracking changes
-  Created structured changelog templates and configuration

.. _documentation-3:

Documentation
~~~~~~~~~~~~~

-  Set up Scriv configuration and directory structure
-  Created README for changelog fragment workflow

.. raw:: html

   <!-- scriv-end-here -->

2.0.0-pre7 - 2025-08-31
======================

.. _added-5:

Added
~~~~~

-  Comprehensive relationships system with three relationship types:

   -  ``tracked_in`` - Multi-presence tracking with score encoding
   -  ``indexed_by`` - O(1) hash-based lookups
   -  ``member_of`` - Bidirectional membership with collision-free
      naming

-  Categorical permission system with bit-encoded permissions
-  Time-based permission scoring for temporal access control
-  Permission tier hierarchies with inheritance patterns
-  Scalable permission management for large object collections
-  Score-based sorting with custom scoring functions
-  Permission-aware queries filtering by access levels
-  Relationship validation framework ensuring data integrity

.. _changed-4:

Changed
~~~~~~~

-  Performance optimizations for large-scale relationship operations

.. _security-2:

Security
~~~~~~~~

-  GitHub Actions security hardening with matrix optimization

2.0.0-pre6 - 2025-08-15
======================

.. _added-6:

Added
~~~~~

-  New ``save_if_not_exists`` method for conditional persistence
-  Atomic persistence operations with transaction support
-  Enhanced error handling for persistence failures
-  Improved data consistency guarantees

.. _changed-5:

Changed
~~~~~~~

-  Connection provider pattern for flexible pooling strategies
-  Multi-database support with intelligent pool management
-  Thread-safe connection handling for concurrent applications
-  Configurable pool sizing and timeout management
-  Modular class structure with cleaner separation of concerns
-  Enhanced feature system with dependency management
-  Improved inheritance patterns for better code organization
-  Streamlined base class functionality

.. _fixed-2:

Fixed
~~~~~

-  Critical security fixes in Ruby workflow vulnerabilities
-  Systematic dependency resolution via multi-constraint optimization

2.0.0-pre5 - 2025-08-05
======================

.. _added-7:

Added
~~~~~

-  Field-level encryption with transparent access patterns
-  Multiple encryption providers:

   -  XChaCha20-Poly1305 (preferred, requires rbnacl)
   -  AES-256-GCM (fallback, OpenSSL-based)

-  Field-specific key derivation for cryptographic domain separation
-  Configurable key versioning supporting key rotation
-  Non-persistent field storage for sensitive runtime data
-  RedactedString wrapper preventing accidental logging/serialization
-  Memory-safe handling of sensitive data in Ruby objects
-  API-safe serialization excluding transient fields

.. _security-3:

Security
~~~~~~~~

-  Encryption field security hardening with additional validation
-  Enhanced memory protection for sensitive data handling
-  Improved key management patterns and best practices
-  Security test suite expansion with comprehensive coverage

2.0.0-pre - 2025-07-25
======================

.. _added-8:

Added
~~~~~

-  Complete API redesign for clarity and modern Ruby conventions
-  Valkey compatibility alongside traditional Valkey/Redis support
-  Ruby 3.4+ modernization with fiber and thread safety improvements
-  Connection pooling foundation with provider pattern architecture

.. _changed-6:

Changed
~~~~~~~

-  ``Familia::Base`` replaced by ``Familia::Horreum`` as the primary
   base class
-  Connection configuration moved from simple string to block-based
   setup
-  Feature activation changed from ``include`` to ``feature``
   declarations
-  Method naming updated for consistency (``delete`` → ``destroy``,
   ``exists`` → ``exists?``, ``dump`` → ``serialize``)

.. _documentation-4:

Documentation
~~~~~~~~~~~~~

-  YARD documentation workflow with automated GitHub Pages deployment
-  Comprehensive migrating guide for v1.x to v2.0.0-pre transition

.. raw:: html

   <!-- scriv-end-here -->
