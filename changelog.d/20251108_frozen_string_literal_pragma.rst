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

- All Ruby files now include consistent headers with ``frozen_string_literal: true`` pragma for improved performance and memory efficiency. Headers follow the format: filename comment, blank comment line, frozen string literal pragma. Executable scripts properly place shebang first.

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

- Claude Sonnet 4.5 automated the addition of consistent file headers with frozen_string_literal pragma across 308 Ruby files, then corrected 35 executable scripts to ensure shebangs remain as the first line.
