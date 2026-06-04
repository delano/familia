Fixed
-----

- ``Horreum.build`` with a block no longer has a TOCTOU race between the
  ``exists?`` check and the ``atomic_write`` commit. The block path now uses
  ``atomic_write(watch_keys:, pre_check:)`` so the existence check runs between
  ``WATCH`` and ``MULTI`` -- if the key is created by a concurrent client in that
  window, Redis aborts the transaction and the method retries with exponential
  backoff (up to 3 attempts). Previously, two concurrent ``build`` calls for the
  same identifier could both pass the check and the later write would win
  silently. #288

Added
-----

- ``atomic_write`` now accepts optional ``watch_keys:`` and ``pre_check:``
  keyword parameters for composing Redis ``WATCH`` into the ``MULTI/EXEC``
  transaction. ``watch_keys`` specifies keys to watch for concurrent
  modification; ``pre_check`` is a callable executed between ``WATCH`` and
  ``MULTI`` (the only window where reads return real values while the watched
  keys are guarded). On ``WATCH`` abort the method retries with exponential
  backoff. This enables optimistic locking patterns without leaving the
  ``atomic_write`` contract. #288

AI Assistance
-------------

- AI implemented WATCH composition into ``atomic_write`` from #288, extracting
  the existing transaction body into ``execute_unwatched_atomic_write`` and adding
  ``execute_watched_atomic_write`` with WATCH + retry logic mirroring
  ``save_if_not_exists!``. Updated ``build`` to pass ``watch_keys:`` and
  ``pre_check:`` instead of the prior bare ``exists?`` guard. Added a dedicated
  tryouts suite verifying the watched path, pre_check rejection, retry on
  simulated WATCH abort, argument validation, and nesting guards.
