.. A new scriv changelog fragment.

Added
-----

- Comprehensive test coverage for ``save`` and ``save_if_not_exists!`` consistency in ``try/integration/save_methods_consistency_try.rb``. The test suite verifies that both methods produce identical results when creating new objects, including timestamp updates, unique index validation, class-level index updates, and instance collection tracking. Tests also confirm that ``save_if_not_exists`` correctly returns ``false`` for existing objects while allowing ``OptimisticLockError`` to propagate for concurrency conflicts.

Fixed
-----

- Fixed ``save_if_not_exists!`` return value to correctly return ``true`` when successfully saving new objects. Previously returned ``false`` despite successful persistence due to incorrect handling of transaction result.

AI Assistance
-------------

- Claude Code created the comprehensive test suite covering 8 categories of consistency checks (24 test cases total), debugged and fixed issues with unique index cleanup, TTL expectations, and email uniqueness, and identified and resolved the return value bug in ``save_if_not_exists!``.
