.. A new scriv changelog fragment.
..
.. This fragment documents the renaming of TimeUtils to TimeLiterals for semantic clarity.
..

Changed
-------

- **BREAKING CHANGE**: Renamed ``Familia::Refinements::TimeUtils`` to ``Familia::Refinements::TimeLiterals`` to better reflect the module's primary purpose of enabling numeric and string values to be treated as time unit literals (e.g., ``5.minutes``, ``"30m".in_seconds``). Functionality remains the same - only the module name has changed. Users must update their refinement usage from ``using Familia::Refinements::TimeUtils`` to ``using Familia::Refinements::TimeLiterals``.

Fixed
-----

- Fixed ExternalIdentifier HashKey method calls by replacing incorrect ``.del()`` calls with ``.remove_field()`` in three critical locations: extid setter (cleanup old mapping when changing value), find_by_extid (cleanup orphaned mapping when object not found), and destroy! (cleanup mapping when object is destroyed). Added comprehensive test coverage for all scenarios to prevent regression. PR #100

AI Assistance
-------------

- Claude Code helped rename TimeUtils to TimeLiterals throughout the codebase, including module name, file path, all usage references, and updating existing documentation.
- Gemini 2.5 Flash wrote the inline docs for TimeLiterals based on a discussion re: naming rationale.
- Claude Code fixed the ExternalIdentifier HashKey method bug, replacing incorrect ``.del()`` calls with proper ``.remove_field()`` calls, and implemented test coverage for the affected scenarios.
