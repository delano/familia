.. A new scriv changelog fragment.
..
.. Uncomment the section that is right (remove the leading dots).
.. For top level release notes, leave all the headers commented out.
..
Added
-----

- Bidirectional reverse collection methods for ``participates_in`` with ``_instances`` suffix (e.g., ``user.project_team_instances``, ``user.project_team_ids``). Supports union behavior for multiple collections and custom naming via ``as:`` parameter. Closes #179.

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

- Claude Opus 4 assisted with implementation of bidirectional participation relationships using ``_instances`` suffix pattern. Pivoted from initial dry-inflector pluralization approach based on feedback.
