Fixed
-----

- ``Familia::MultiResult`` no longer raises ``NoMethodError`` when it wraps an
  aborted transaction. A WATCH-guarded ``MULTI`` whose watched key is modified
  by another client has its ``EXEC`` discarded, and redis-rb returns ``nil``
  rather than an array of command results — so ``errors``, ``errors?``,
  ``successful?``, ``size``, and ``to_h`` all blew up on ``nil`` instead of
  reporting the transaction as unsuccessful. A caller doing the right thing
  (checking ``result.successful?`` and retrying on contention) crashed exactly
  when contention occurred. An aborted result now reports ``successful? ==
  false`` with an empty ``errors`` array and ``size == 0``, and ``results``
  still holds ``nil`` so an abort remains distinguishable from a transaction
  that committed zero commands. #355

Added
-----

- ``Familia::MultiResult#aborted?`` reports whether a transaction was discarded
  before ``EXEC`` ran, letting callers tell a WATCH abort (retry) apart from a
  transaction where an individual command failed (inspect ``errors``). Note the
  resulting asymmetry: an aborted transaction is not ``successful?``, yet
  ``errors?`` is false — it ran no commands, so no command errored.

AI Assistance
-------------

- Claude Code implemented the nil-result handling, added
  ``try/unit/multi_result_try.rb`` covering clean, error-carrying, empty, and
  aborted results plus a real WATCH-aborted ``MULTI`` driven against the
  database from two connections, and switched
  ``TransactionCore.execute_watched_transaction``'s abort detection to the new
  ``aborted?`` predicate.
