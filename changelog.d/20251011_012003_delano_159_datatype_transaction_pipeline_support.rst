.. Added
.. -----
.. New features and capabilities that have been added.

.. Changed
.. -------
.. Changes to existing functionality.

.. Deprecated
.. ----------
.. Soon-to-be removed features.

.. Removed
.. -------
.. Now removed features.

.. Fixed
.. -----
.. Bug fixes.

.. Security
.. --------
.. Security-related improvements.

Added
-----

-  **DataType Transaction and Pipeline Support** - DataType objects can now initiate transactions and pipelines independently, enabling atomic operations and batch command execution for both parent-owned and standalone DataType objects. `PR #159 <https://github.com/familia/familia/pull/159>`_

   Key capabilities added:

   * ``transaction`` method for atomic MULTI/EXEC operations on all DataType classes
   * ``pipelined`` method for batched command execution on all DataType classes
   * Connection chain pattern with Chain of Responsibility for DataType objects
   * Two new connection handlers: ``ParentDelegationHandler`` for owned DataTypes and ``StandaloneConnectionHandler`` for independent DataTypes
   * Enhanced ``direct_access`` method with automatic transaction/pipeline context detection
   * Shared ``Familia::Connection::Behavior`` module extracting common connection functionality

   This enhancement addresses a critical gap where standalone DataType objects (like those used in Rack::Session implementations) could not guarantee atomicity across multiple operations. Both parent-owned DataTypes (delegating to parent Horreum objects) and standalone DataTypes now support the full transaction and pipeline API.

   Example usage:

   .. code-block:: ruby

      # Parent-owned DataType transaction
      user.scores.transaction do |conn|
        conn.zadd(user.scores.dbkey, 100, 'level1')
        conn.zadd(user.scores.dbkey, 200, 'level2')
      end

      # Standalone DataType transaction
      session_store = Familia::StringKey.new('session:abc123')
      session_store.transaction do |conn|
        conn.set(session_store.dbkey, data)
        conn.expire(session_store.dbkey, 3600)
      end

      # Pipeline for performance optimization
      leaderboard.pipelined do |pipe|
        pipe.zadd(leaderboard.dbkey, 500, 'player1')
        pipe.zadd(leaderboard.dbkey, 600, 'player2')
        pipe.zcard(leaderboard.dbkey)
      end

Changed
-------

-  **DataType URI Construction** - DataType objects with ``logical_database`` settings now return clean URIs without custom port information (e.g., ``redis://127.0.0.1/3`` instead of ``redis://127.0.0.1:2525/3``), ensuring consistent URI representation across the library.

AI Assistance
-------------

This feature was implemented with significant AI assistance from Claude (Anthropic). The AI helped with:

* Architectural design of the connection chain pattern for DataType objects
* Implementation of the shared Behavior module to extract common functionality
* Creation of DataType-specific connection handlers (ParentDelegationHandler, StandaloneConnectionHandler)
* Comprehensive test coverage including transaction and pipeline integration tests
* Documentation and changelog preparation
* Debugging and fixing URI formatting edge cases

The implementation preserves backward compatibility (all 2,216 existing tests pass) while adding 27 new tests specifically for DataType transaction and pipeline support.
