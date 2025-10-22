.. A new scriv changelog fragment.

.. Uncomment the header that is right (remove the leading dots).

Fixed
-----

- **Connection Chain Race Condition**: Fixed race condition in connection chain lazy initialization where concurrent calls to ``Familia.dbclient`` and ``Familia.reconnect!`` could create multiple chain instances instead of maintaining singleton property. Added Mutex protection with ``@connection_chain_mutex`` initialized at module load time to ensure thread-safe lazy initialization. The fix prevents 50 duplicate chain instances from being created under maximum contention (verified with CyclicBarrier testing). See ``lib/familia/connection.rb:99`` and ``lib/familia/connection/middleware.rb:86``.

- **Thread Safety Test Suite**: Corrected test assertions to verify actual thread safety invariants. Tests were checking Redis client object IDs instead of connection chain object IDs, and expecting ``RedisClient`` class name instead of ``Redis``. With corrected assertions, tests now properly verify singleton property and successfully detect the race condition fixed above. Test suite status: **56/56 passing** (2 tests corrected from false negatives).

Added
-----

- **Advanced Testing Patterns**: Documented 5 reusable concurrency testing patterns in thread safety README: Structure Validation, Concurrent Clearing, Mixed Operation Types, Rapid Sequential Calls, and Type/Method Validation. These patterns enable effective thread safety testing across any concurrent code.

- **Middleware Thread Safety Tests**: Restored comprehensive middleware thread safety test file (was .txt, now .rb) with sophisticated tests covering concurrent append operations, mixed operations, rapid sequential calls, concurrent clearing, and structure preservation under concurrency.

- **Pipeline Routing Investigation**: Created 7 diagnostic testcases in ``try/investigation/pipeline_routing/`` to investigate suspected middleware routing issue. Investigation revealed single-command pipelines don't have ' | ' separator (expected Array#join behavior), confirming no routing bug exists. Full analysis documented in ``CONCLUSION.md``.

Changed
-------

- **Test Suite Cleanup**: Removed 2 tests with incorrect expectations after investigation proved they were testing wrong assumptions rather than actual bugs: (1) sample_rate counter test at ``middleware_thread_safety_try.rb:113`` - sample_rate intentionally controls logging output, not command capture; (2) pipeline command logging test at ``middleware_thread_safety_try.rb:224`` - single-command pipelines correctly don't have ' | ' separator per Array#join behavior.

AI Assistance
-------------

- Claude Code assisted with:

  - Analyzing PR feedback about weak test assertions and evaluating each failure as potential production bug
  - Investigating git history to understand test evolution
  - Applying multi-property assertion patterns from middleware tests to connection chain tests
  - Extracting and documenting reusable testing patterns
  - Working with backend-dev agent to create isolated pipeline routing diagnostic testcases
  - Systematically investigating each test failure to distinguish real bugs from test assumption errors
  - Identifying and fixing the connection chain race condition with proper Mutex protection
  - Verifying the race condition exists by testing without the Mutex fix (confirmed 50 duplicate instances)
  - Correcting test expectations to match actual class names and verify correct invariants
  - Creating comprehensive documentation of test suite status, race condition analysis, and fixes

  This work involved extensive git archaeology, pattern recognition across test files, systematic debugging using isolated testcases, collaboration with specialized agents, defensive programming with Mutex protection, and rigorous testing to verify the fix resolves the race condition.

.. Uncomment the section that is right (remove the leading dots).
.. Choose from: Added, Changed, Deprecated, Fixed, Removed, Security, Documentation, AI Assistance

.. .. code-block:: rst
..
..   .. Added
..   .. -----
..
..   - A new feature here.
..   - Another new feature.
..
..   .. Changed
..   .. -------
..
..   - A change to an existing feature.
..
..   .. Deprecated
..   .. ----------
..
..   - A feature that is now deprecated.
..
..   .. Fixed
..   .. -----
..
..   - A bug fix.
..   - Another bug fix.
..
..   .. Removed
..   .. -------
..
..   - A feature that has been removed.
..
..   .. Security
..   .. --------
..
..   - A security improvement or fix.
..
..   .. Documentation
..   .. -------------
..
..   - A documentation improvement.
..
..   .. AI Assistance
..   .. -------------
..
..   - Claude Code assisted with X, Y, and Z.
..   - Discussion and rubber ducking around approach to A, B, C.
..   - Writing tests for feature D.
