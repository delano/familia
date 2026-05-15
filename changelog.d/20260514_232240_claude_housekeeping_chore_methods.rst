Added
~~~~~

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

Changed
~~~~~~~

- ``housekeeping`` feature: split the dual-purpose ``tidy!`` into two
  explicit instance methods. ``do_chore!(name)`` runs a single named
  chore and returns the block's raw return value (no longer wrapped
  in a ``{name => result}`` hash). ``do_chores!`` runs every
  registered chore and returns the ``{name => result}`` hash.
  ``tidy!`` is preserved as an alias of ``do_chores!`` for backwards
  compatibility with the 2.7.0 no-arg call site; the single-arg form
  ``tidy!(:name)`` now raises ``ArgumentError``.

AI Assistance
~~~~~~~~~~~~~

- Method split, alias wiring, bulk runner port from OTS, doc updates,
  and expanded tryouts coverage (25 → 48 testcases) authored with
  Claude Code.
