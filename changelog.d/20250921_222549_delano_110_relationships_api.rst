.. A new scriv changelog fragment.
..
.. Uncomment the section that is right (remove the leading dots).
.. For top level release notes, leave all the headers commented out.
..
.. Added
.. -----
..
.. - A bullet item for the Added category.
..

Changed
-------

- **BREAKING**: Consolidated relationships API by replacing ``tracked_in`` and ``member_of`` with unified ``participates_in`` method. PR #110
- **BREAKING**: Renamed ``context_class`` terminology to ``target_class`` throughout relationships module for clarity
- **BREAKING**: Removed ``tracking.rb`` and ``membership.rb`` modules, merged functionality into ``participation.rb``
- **BREAKING**: Updated method names and configuration keys to use ``target`` instead of ``context`` terminology
- Added ``bidirectional`` parameter to ``participates_in`` to control generation of convenience methods (default: true)
- Added support for different collection types (sorted_set, set, list) in unified ``participates_in`` API
- Renamed ``class_tracked_in`` to ``class_participates_in`` for consistency

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

- Comprehensive analysis of existing ``tracked_in`` and ``member_of`` implementations
- Design and implementation of unified ``participates_in`` API integrating both functionalities
- Systematic refactoring of codebase terminology from context to target
- Complete test suite updates to verify API consolidation and new functionality
