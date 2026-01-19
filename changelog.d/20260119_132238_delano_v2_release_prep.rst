Familia 2.0.0 represents a complete rewrite of the library with 26 pre-release
iterations incorporating community feedback and production testing.

Added
-----

- **Modular Feature System**: Autoloading features with ancestry chain traversal
  (``feature :expiration``, ``feature :relationships``, etc.)
- **Unified Relationships API**: ``participates_in`` replaces ``tracked_in``/``member_of``
  with bidirectional reverse lookups (``_instances`` suffix methods)
- **Type-Safe Serialization**: JSON encoding preserves Integer, Boolean, Float,
  Hash, Array types across Redis boundary
- **Performance Optimizations**: Pipelined bulk loading (``load_multi``),
  optional EXISTS check (``check_exists: false``), OJ JSON for 2-5× faster operations
- **Security Features**: VerifiableIdentifier with HMAC signatures,
  ExternalIdentifier with format flexibility, encrypted fields with key rotation
- **Thread Safety**: Mutex initialization fixes, 56-test thread safety suite
- **Instrumentation**: ``Familia.on_command``, ``Familia.on_pipeline``,
  ``Familia.on_lifecycle`` hooks for monitoring

Changed
-------

- **BREAKING**: DataType class renaming to avoid Ruby namespace conflicts
  (``Familia::String`` → ``Familia::StringKey``, etc.)
- **BREAKING**: Removed ``dump_method``/``load_method`` - JSON serialization is now standard
- **BREAKING**: Indexing API renamed (``class_indexed_by`` → ``unique_index``,
  ``indexed_by`` → ``multi_index``)

Documentation
-------------

- Archived 11 pre-release migration guides to ``docs/.archive/``
- Enhanced ``api-technical.md`` with bulk loading, EXISTS optimization,
  per-class feature registration, and index rebuilding documentation
- Updated version references and fixed broken anchor links throughout docs

AI Assistance
-------------

- Claude Opus 4.5 coordinated 11 parallel code-explorer agents to evaluate
  migration docs, identifying unique content to preserve before archiving.
  Assisted with release statistics gathering and documentation consolidation.
