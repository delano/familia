.. A new scriv changelog fragment.

Fixed
-----

- Fixed ``save_if_not_exists!`` to perform the same operations as ``save`` when creating new objects. Previously, ``save_if_not_exists!`` omitted timestamp updates (``created``/``updated``), unique index validation (``guard_unique_indexes!``), and adding to the instances collection. Now both methods produce identical results when saving a new object, with ``save_if_not_exists`` only differing in its conditional existence check.

Changed
-------

- Refactored ``save`` and ``save_if_not_exists!`` to use shared helper methods (``prepare_for_save`` and ``persist_to_storage``) to eliminate code duplication and ensure consistency. Both methods now follow the same preparation and persistence logic, differing only in their concurrency control patterns (simple transaction vs. optimistic locking with WATCH).

Documentation
-------------

- Streamlined inline documentation for ``save``, ``save_if_not_exists!``, and ``save_if_not_exists`` methods to be more concise, internally consistent, and non-redundant. Each method's documentation now stands on its own with clear, focused descriptions.

AI Assistance
-------------

- Claude Code identified the inconsistencies between ``save`` and ``save_if_not_exists!`` methods, implemented the fixes, refactored both methods to extract shared logic into private helper methods (``prepare_for_save`` and ``persist_to_storage``), and updated the documentation to be more concise and internally consistent.
