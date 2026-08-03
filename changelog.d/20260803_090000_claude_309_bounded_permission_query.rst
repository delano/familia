Fixed
-----

- Bounded the generated ``<collection>_with_permission`` participation query,
  which previously materialized the entire sorted set per call. Permission bits
  live in the fractional part of the score and are not a contiguous range, so
  they can never be filtered server-side; the query now pages internally via
  ``ZRANGEBYSCORE ... LIMIT`` in ``batch_size:`` chunks (default 500), keeping
  peak memory at O(batch_size) instead of O(N). Results are identical for
  collections not being concurrently modified; unlike the old single-command
  fetch, the paged read is not an atomic snapshot. #309

Added
-----

- ``limit:`` and ``offset:`` keyword arguments on
  ``<collection>_with_permission`` count *matching* members (post-filter
  semantics), enabling pagination in deterministic score order, and a new
  ``each_<collection>_with_permission(min_permission = :read, batch_size: 100)``
  sibling streams matches via ``ZSCAN`` with O(1) retained memory — unordered,
  at-least-once delivery — returning an ``Enumerator`` when called without a
  block. #309

AI Assistance
-------------

- AI implemented the bounded/streaming query forms recommended by the memory
  audit's #309 diagnosis and updated the relationships documentation
  (``docs/overview.md``, the participation guide, and rdoc comments) to match.
