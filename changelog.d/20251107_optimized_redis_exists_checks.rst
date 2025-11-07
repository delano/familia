.. Added
.. -----

- **Pipelined Bulk Loading Methods**: New `load_multi` and `load_multi_by_keys` methods enable efficient bulk object loading using Redis pipelining. These methods reduce network round trips from N×2 commands (EXISTS + HGETALL per object) to a single pipelined batch of HGETALL commands.

  **Standard loading** (N objects, N×2 commands):

  .. code-block:: ruby

     users = ids.map { |id| User.find_by_id(id) }
     # For 14 objects: 28 Redis commands (14 EXISTS + 14 HGETALL)

  **Pipelined bulk loading** (N objects, 1 round trip):

  .. code-block:: ruby

     users = User.load_multi(ids)
     # For 14 objects: 1 pipelined batch with 14 HGETALL commands
     # Up to 2N× performance improvement

  **Load by identifiers**:

  .. code-block:: ruby

     metadata_objects = Metadata.load_multi(['id1', 'id2', 'id3'])
     # Returns array: [obj1, obj2, obj3]

     # Filter out nils for missing objects
     existing_only = Metadata.load_multi(ids).compact

  **Load by full dbkeys**:

  .. code-block:: ruby

     keys = ['user:123:object', 'user:456:object']
     users = User.load_multi_by_keys(keys)

  The methods maintain the same nil-return contract as `find_by_id` for non-existent objects, preserve input order, and properly deserialize all Horreum field types. Ideal for loading collections of related objects, processing query results, or any scenario requiring multiple object lookups.

.. Changed
.. -------

- **Optional EXISTS Check Optimization**: The `find_by_dbkey` and `find_by_identifier` methods now accept a `check_exists:` parameter (default: `true`) to optionally skip the EXISTS check before HGETALL. This reduces Redis commands from 2 to 1 per object while maintaining backwards compatibility.

  **Safe mode** (default behavior, 2 commands):

  .. code-block:: ruby

     user = User.find_by_id(123)
     # Commands: EXISTS user:123:object, then HGETALL user:123:object

  **Optimized mode** (1 command):

  .. code-block:: ruby

     user = User.find_by_id(123, check_exists: false)
     # Command: HGETALL user:123:object only
     # Returns nil if key doesn't exist (empty hash detected)

  **Use cases for optimized mode**:

  - Performance-critical paths where 50% reduction matters
  - Bulk operations with known-to-exist keys
  - High-throughput APIs processing collections
  - Loading objects from sorted set members (ZRANGEBYSCORE results)

  The optimization is backwards compatible (default unchanged) and maintains the same nil-return behavior for non-existent keys by detecting empty hashes returned from HGETALL.

.. Deprecated
.. ----------

.. Removed
.. -------

.. Fixed
.. -----

.. Security
.. --------

.. Documentation
.. -------------

.. AI Assistance
.. -------------

- **Performance Analysis**: Claude Code analyzed the Redis command trace log provided by the user, identifying the EXISTS + HGETALL pattern as the performance bottleneck in bulk object loading scenarios.
- **Solution Design**: Claude Code designed a multi-faceted optimization approach: (1) optional EXISTS check bypass with backwards compatibility, (2) pipelined bulk loading methods, (3) comprehensive test coverage. The design balanced performance gains with API safety and backwards compatibility.
- **Implementation**: Claude Code implemented both optimization strategies including parameter additions, new bulk loading methods, comprehensive documentation with performance characteristics, and 28 test cases covering all scenarios including edge cases (nil identifiers, missing objects, order preservation).
- **Code Review**: Claude Code ensured the implementation follows Familia's existing patterns for field deserialization, maintains nil-return contracts, and properly handles Redis::Future objects in transaction contexts.
