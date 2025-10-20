.. A new scriv changelog fragment.

Fixed
-----

- Fixed ``save_if_not_exists!`` to perform the same operations as ``save`` when creating new objects. Previously, ``save_if_not_exists!`` omitted timestamp updates (``created``/``updated``), unique index validation (``guard_unique_indexes!``), and adding to the instances collection. Now both methods produce identical results when saving a new object, with ``save_if_not_exists`` only differing in its conditional existence check.

AI Assistance
-------------

- Claude Code identified the inconsistencies between ``save`` and ``save_if_not_exists!`` methods, implemented the fixes by adding timestamp updates, unique index validation, and instances collection updates to ``save_if_not_exists!``, and updated the documentation to reflect the changes.
