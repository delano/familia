Fixed
-----

- Eliminated a transient read window during index rebuilds where concurrent
  ``HGET`` on an index key could return ``nil``. ``RebuildStrategies.atomic_swap``
  previously ran ``DEL`` followed by ``RENAME`` as two separate commands, leaving
  the final key absent in between. It now relies on ``RENAME``'s native atomic
  replacement, so readers never observe a missing index during rebuild. Issue #247

AI Assistance
-------------

- Issue triage, fix, and race-detection test authored with Claude Code
  assistance. Issue #247
