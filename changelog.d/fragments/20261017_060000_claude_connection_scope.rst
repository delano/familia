Added
-----

- Added ``Familia.with_connection_scope(uri = nil) { |client| ... }``. While
  the block runs, every ``dbclient`` lookup in the calling fiber that would
  otherwise reach ``CreateConnectionHandler`` (no ``connection_provider``, no
  class-level ``@dbclient``) resolves to one ``Redis`` client per distinct
  connection configuration (keyed by ``URI#conf``), created on first use with
  ``Familia.create_dbclient``. The scope closes every client it created when
  the block exits, on return and on exception. The block receives the scope's
  client for ``uri`` (``Familia.uri`` when nil). A nested call in the same
  fiber joins the open scope. ``transaction``, ``pipelined`` and
  ``atomic_write`` inside the block run on the scope's client for their URI.
  Between the WATCH and the EXEC of a WATCH-guarded transaction, other
  lookups get a second scope client for that URI, so a transaction they run
  cannot clear the WATCH.
  Threads and fibers spawned inside the block are not the owner and resolve
  connections as if no scope were open. A ``Familia.middleware_version`` bump
  (``Familia.reconnect!``) makes the scope retire its clients on the next
  lookup: new lookups get fresh clients and the retired ones stay open until
  the block exits. A fiber-local connection, a ``connection_provider`` and a
  class-level ``@dbclient`` take precedence over the scope. Connection
  resolution outside a scope is unchanged: without a provider, lookups still
  create fresh clients. (issue #456)
- Added ``Familia.current_connection_scope``, returning the
  ``Familia::Connection::Scope`` the current fiber has open, or nil.
- Added ``Familia::Connection::Scope`` with ``owner``, ``clients``, ``size``,
  ``active?``, ``released?`` and ``release!``. ``release!`` closes every held
  client and is safe to call more than once; a later ``Scope#client`` call
  raises ``Familia::Problem``, as does a ``client`` or ``release!`` call from
  a fiber other than the owner.
- Added ``Familia::Connection::ScopedConnectionHandler`` (``supports
  transaction: true, pipelined: true``), placed after
  ``ProviderConnectionHandler`` in the ``Familia.dbclient`` chain and after
  ``CachedConnectionHandler`` in the Horreum class chain, before
  ``CreateConnectionHandler`` in both. The DataType chain is unchanged; it
  reaches the scope through the parent's chain or ``Familia.dbclient``.
- Added ``with_connection_scope(uri = nil)`` to Horreum classes and DataType
  instances through ``Familia::Connection::Behavior``, and to Horreum
  instances, which forward to their class. It opens the same scope and yields
  the client resolved through the receiver's own chain, so a class-level
  ``@dbclient`` or ``logical_database`` setting is honoured.

Documentation
-------------

- Documented connection scopes in ``docs/reference/api-technical.md``
  (``Connection Scopes``, with Rack middleware and job examples) and
  ``docs/guides/index.md``, and corrected the resolution order listed under
  ``Connection Chain Debugging``.

AI Assistance
-------------

- The feature and its documentation were developed with AI assistance.
