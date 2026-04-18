Added
-----

- ``Familia::AtomicOperations`` module for zero-downtime key swaps.
  Exposes ``atomic_swap(temp_key, final_key, redis)`` and
  ``build_temp_key(base_key)`` as reusable primitives for any
  rebuild-then-swap workflow. ``atomic_swap`` relies on Redis's native
  ``RENAME`` atomicity to replace a key's contents in a single server
  step, with a ``DEL``-only branch when the rebuilt temp key is empty.
  Intended reuse includes audit/repair flows, index rebuilds, and any
  other swap-in-place pattern that previously had to hand-roll the
  same sequence. PR #221

Changed
-------

- ``Familia::Features::Relationships::Indexing::RebuildStrategies`` no
  longer defines ``atomic_swap`` and ``build_temp_key`` directly. The
  methods were relocated to ``Familia::AtomicOperations`` and all
  internal call sites now delegate there. This is a pure refactor: the
  race semantics established in PR #247 (reliance on native ``RENAME``
  atomicity) are preserved verbatim. The two methods were not part of a
  documented public API; any downstream code calling them directly on
  ``RebuildStrategies`` should switch to
  ``Familia::AtomicOperations.atomic_swap`` /
  ``Familia::AtomicOperations.build_temp_key``. PR #221

AI Assistance
-------------

- Extraction of ``atomic_swap`` and ``build_temp_key`` into the new
  ``Familia::AtomicOperations`` module, and the corresponding
  delegation updates in ``RebuildStrategies``, were authored with AI
  assistance.
