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
  false`` with an empty ``errors`` array and ``size == 0``. #355

Added
-----

- ``Familia::MultiResult#aborted?`` reports whether a transaction was discarded
  before ``EXEC`` ran, letting callers tell a WATCH abort (retry the whole
  transaction) apart from one where an individual command failed (inspect
  ``errors``). Note the deliberate asymmetry: an aborted transaction is not
  ``successful?``, yet ``errors?`` is false — it ran no commands, so no command
  errored. ``successful?`` remains the method to test for the overall outcome.

- ``Familia::MultiResult#inspect`` summarizes the outcome
  (``#<Familia::MultiResult aborted size=0>``) instead of using the default
  object dump. It deliberately omits the command return values, which
  routinely carry field values read back out of the database and have no
  business landing in a log line by default.

Changed
-------

- ``Familia::MultiResult#results`` is now always an Array. It previously
  exposed redis-rb's raw return value, which is ``nil`` for an aborted
  transaction, pushing a nil check onto every caller that indexes or iterates
  it — the same class of crash as #355, one level out. An abort now reports an
  empty array, and ``#aborted?`` carries the distinction the ``nil`` used to
  carry:

  .. code-block:: ruby

     # before
     result.results        # => nil on a WATCH abort
     result.results.nil?   # the only way to detect an abort

     # after
     result.results        # => [] on a WATCH abort
     result.aborted?       # => true
     result.results[0]     # => nil, instead of NoMethodError

  Code testing ``results.nil?`` to detect an abort should call ``aborted?``.
  Note that an abort and a transaction that committed zero commands both
  report ``results == []``; ``aborted?`` is what separates them.

- ``Familia::MultiResult#to_h`` gained an ``:aborted`` key, so a dumped
  failure says why it failed rather than reading as a result whose errors went
  missing. ``to_h`` now returns ``{success:, aborted:, results:}``. Code
  comparing the hash by equality needs the extra key.

- ``Familia::MultiResult`` instances are now read-only: both ``#results`` and
  ``#errors`` are frozen. ``#errors`` was previously frozen only for aborted
  results, so mutating it succeeded or raised depending on the outcome. And
  because ``#errors`` is a memo derived from ``#results``, a mutable
  ``#results`` let the two drift — appending an exception after ``#errors``
  had been read left a stale error list, and ``to_h[:results]`` handed out a
  live reference to internal state. A result describes an operation that has
  already finished, so neither array was ever meaningful to modify. Code that
  mutates either in place should work on a ``dup``.

AI Assistance
-------------

- Claude Code implemented the nil handling and the accessor normalization,
  added ``try/unit/multi_result_try.rb`` covering clean, error-carrying,
  empty, and aborted results across every accessor and alias — including that
  an abort stays distinguishable from a zero-command commit — plus a real
  WATCH-aborted ``MULTI`` driven against the database from two connections,
  and switched ``TransactionCore.execute_watched_transaction``'s abort
  detection to the new ``aborted?`` predicate.
