Fixed
-----

- Two latent encryption bugs surfaced while repairing the examples (issue
  #250):

  - ``Familia::Encryption.with_request_cache`` and ``clear_request_cache!``
    were unreachable. The implementation lived in
    ``lib/familia/encryption/request_cache.rb``, which was never ``require``\ d,
    so calling the documented request-cache API raised ``NoMethodError``.
    The file is now loaded with the rest of the encryption stack.

  - The XChaCha20-Poly1305 provider derived keys with
    ``context.force_encoding('BINARY')``, mutating the caller's string. A
    frozen context (e.g. the literal used by ``Familia::Encryption.benchmark``)
    raised ``FrozenError``. It now uses ``context.b`` to operate on a copy.

Documentation
-------------

- Repaired every script in ``examples/`` so each runs top-to-bottom and is
  re-runnable (issue #250):

  - ``encrypted_fields.rb``: all nine ``ConcealedString#reveal`` call sites
    now use the required block form; example keys are valid 32-byte keys;
    the memory-safety example captures the ``ConcealedString`` before
    ``clear!`` instead of re-reading through the (context-validated) getter.

  - ``relationships.rb``: migrated off the renamed-away
    ``class_indexed_by``/``get_by_*`` API to the current v2 DSL
    (``unique_index``/``multi_index``/``find_by_*``/``find_all_by_*``,
    the built-in ``instances`` timeline, and explicit
    ``class_participates_in`` population); object identifiers are no longer
    commented out; added a teardown so ``unique_index`` does not collide on
    re-run.

  - ``safe_dump.rb``: cleanup now splats keys into ``del`` with an
    empty-guard and uses the correct ``config_name`` key prefix (the same
    prefix fix was applied to ``encrypted_fields.rb`` cleanup).

- Added ``try/integration/examples/`` with one subprocess-driven tryouts
  file per example script, so the examples directory now has automated
  regression coverage and cannot rot silently again.

AI Assistance
-------------

- Claude diagnosed and fixed the broken example scripts and the two latent
  encryption bugs they surfaced, verified each script runs and is
  idempotent, and authored the subprocess-driven regression tryouts. Issue
  #250.
