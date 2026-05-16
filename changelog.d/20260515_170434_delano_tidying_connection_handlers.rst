Removed
-------

- ``Familia::DataType#direct_access`` has been removed. The method was a legacy escape hatch for issuing raw Redis commands from inside a DataType wrapper; it predates the chain-based routing of ``Fiber[:familia_transaction]`` and ``Fiber[:familia_pipeline]``. All in-tree call sites now go through the wrapper's own mutating methods (which auto-route through the active transaction or pipeline) or through the wrapper's ``transaction`` / ``pipelined`` blocks. If you were calling ``direct_access do |conn, key| ... end``, replace it with either the DataType's own mutator or the corresponding block API.

Changed
-------

- The connection handler hierarchy has been refactored from class inheritance (``BaseConnectionHandler``) to module composition. Handlers now ``include Familia::Connection::Handler`` and declare their operation-mode capabilities with a small DSL: ``supports transaction: true, pipelined: false``. The ``BaseConnectionHandler`` constant is gone. This is only relevant if you have custom handlers in application code — the public ``allows_transaction`` / ``allows_pipelined`` class methods continue to work, and the singleton ``.instance`` accessors on ``FiberPipelineHandler`` / ``FiberTransactionHandler`` are unchanged. The previous default of "allow all operations" when capability flags were not set has been removed; every handler is now expected to declare its capabilities explicitly via ``supports``.
- ``Familia.dbclient`` and ``Familia::DataType#dbclient`` now route through ``FiberPipelineHandler`` before ``FiberTransactionHandler``, matching ``Horreum#dbclient``. With both handlers in the chain, attempting to mix pipeline and transaction contexts raises ``Familia::ConflictingContextError`` uniformly from every call site.

Fixed
-----

- Restored ``require 'set'`` in ``lib/familia/horreum/management/audit.rb``. ``Set`` is autoloaded as a core class only on Ruby 3.4+; on Ruby 3.2/3.3 (the gem's supported floor) the require is mandatory for the five ``Set.new`` usages in that file.

AI Assistance
-------------

- The handler refactor, ``direct_access`` removal, and changelog drafting were performed with Claude Code assistance while resolving review feedback on PR #263.
