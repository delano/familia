.. A new scriv changelog fragment.
..
.. Uncomment the section that is right (remove the leading dots).
.. For top level release notes, leave all the headers commented out.
..
Added
-----

- Bidirectional reverse collection methods for ``participates_in`` relationships. When a class calls ``participates_in TargetClass, :collection_name``, the participant class now automatically gains pluralized convenience methods (e.g., ``user.project_teams``, ``user.project_teams_ids``, ``user.project_teams?``, ``user.project_teams_count``) that provide efficient access to all instances of the target class the participant belongs to. This creates true symmetric relationship access, eliminating manual parsing of participation keys. Supports union behavior (multiple collections automatically merged), custom naming via ``as:`` parameter, and efficient ID-only operations. See issue #179.

.. Changed
.. -------
..
.. - A bullet item for the Changed category.
..
.. Deprecated
.. ----------
..
.. - A bullet item for the Deprecated category.
..
.. Removed
.. -------
..
.. - A bullet item for the Removed category.
..
.. Fixed
.. -----
..
.. - A bullet item for the Fixed category.
..
.. Security
.. --------
..
.. - A bullet item for the Security category.
..
.. Documentation
.. -------------
..
.. - A bullet item for the Documentation category.
..
AI Assistance
-------------

- Claude Opus 4 assisted with comprehensive implementation including: analyzing existing asymmetric participation pattern, designing bidirectional solution with pluralized method names, implementing union behavior for multiple collections, integrating dry-inflector for automatic pluralization, fixing multiget vs load_multi for Horreum objects, creating collection filtering logic, writing test file with 30 test cases, and iterative debugging to achieve 90% test pass rate.
