Added
-----

- ``dirty_write_warnings`` class method on every ``Familia::Horreum`` subclass,
  mirroring ``Familia.strict_write_order`` but scoped to a single class. Accepts
  ``:strict`` (raise), ``:warn`` (warn on every collection write), ``:once``
  (warn once per dirty-field signature per window), or ``:off`` (suppress). The
  setting inherits through the subclass chain, so seed scripts, bulk importers,
  and known-safe call sites can opt down without touching the global. Issue #277

- ``Familia.dirty_write_warnings`` global setting providing the default mode for
  classes that do not set their own. ``Familia.dirty_write_warnings = :off``
  temporarily and restorably silences dirty-write warnings across all such
  classes. Issue #277

Changed
-------

- Dirty-write warnings are now **deduplicated per dirty window** by default. A
  collection write (``SADD``, ``RPUSH``, ``ZADD``, ``HSET``, ``SET``) on a
  parent with unsaved scalar fields now warns once per distinct set of unsaved
  fields, rather than once per write. Creating one object with several
  collections previously emitted 7-10 identical warnings; it now emits one. The
  warning fires again if the set of unsaved fields changes (genuinely new
  information), and the window resets on ``clear_dirty!`` (which ``save``,
  ``commit_fields``, ``batch_update``, and ``refresh`` already call). This
  changes the **default mode from the old every-write behavior to ``:once``**;
  set ``dirty_write_warnings :warn`` (per class) or
  ``Familia.dirty_write_warnings = :warn`` (global) to restore the previous
  output. ``Familia.strict_write_order = true`` is unaffected -- it still raises
  (and is exempt from deduplication) for every class that has not opted out via
  ``:off``. Issue #277

- Dirty-write warning and strict-mode raise messages now append the remediation
  hint ``(call #save first or wrap in atomic_write)``, so the fix is self-evident
  without a round trip to the docs. Issue #277

- ``dirty_write_warnings`` is a per-class severity dial that composes with the
  ``raise_on_unsaved_parent_write`` safety raise added in #278. For a class that
  has *not* opted out, the raise paths (global ``strict_write_order``, a class
  ``:strict``, and a new/unsaved parent when ``raise_on_unsaved_parent_write`` is
  true) fire independently of the warn level -- so a ``:once``/``:warn`` class
  still raises on a new, unsaved parent by default. An explicit ``:off`` is
  authoritative for the class, however: it suppresses the dirty-write guard
  entirely (no warning **and** no raise) and overrides both global raise switches,
  consistent with how an explicit "off"/"ignore" beats a global
  warnings-as-errors escalation in other tools (ESLint, RuboCop, ``-Werror`` +
  ``#pragma`` ignored, Python ``warnings``). All emitted messages carry the
  remediation hint. Issue #277

AI Assistance
-------------

- AI implemented the full change from the issue specification: the per-instance
  deduplication primitive (``record_dirty_warning!`` backed by
  ``Concurrent::Map#put_if_absent``, mirroring ``mark_dirty!``), the dedup-window
  reset in ``clear_dirty!``, the resolution in ``DataType#warn_if_dirty!``
  (atomic_write suppression and an explicit ``:off`` short-circuit first; then the
  raise paths -- global strict, class ``:strict``, or a new/unsaved parent;
  otherwise warn per ``:once``/``:warn``), and the class/global settings with
  validation and subclass-chain inheritance. AI also authored the tryouts coverage in
  ``try/features/dirty_write_warnings_try.rb`` (dedup, signature-change
  re-emission, full and partial ``clear_dirty!`` resets, ``:warn``/``:once``/
  ``:off``/``:strict`` modes, global precedence and fallback, and ``atomic_write``
  priority over ``:strict``) and verified no regressions against the existing
  ``atomic_write``, ``dirty_tracking``, ``list_commands``, and thread-safety
  suites.
