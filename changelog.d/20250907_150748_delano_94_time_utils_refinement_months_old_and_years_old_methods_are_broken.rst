.. A new scriv changelog fragment.

Fixed
-----

- Fixed TimeUtils refinement ``months_old`` and ``years_old`` methods returning incorrect values (raw seconds instead of months/years). The underlying ``age_in`` method now properly handles ``:months`` and ``:years`` units. Issue #94.
- Fixed calendar consistency issue where ``12.months != 1.year`` by updating ``PER_YEAR`` to use Gregorian year (365.2425 days) and defining ``PER_MONTH`` as ``PER_YEAR / 12``.

Added
-----

- Added ``PER_MONTH`` constant (2,629,746 seconds = 30.437 days) derived from Gregorian year for consistent month calculations.
- Added ``months``, ``month``, and ``in_months`` conversion methods to Numeric refinement.
- Added month unit mappings (``'mo'``, ``'month'``, ``'months'``) to TimeUtils ``UNIT_METHODS`` hash.

Changed
-------

- Updated ``PER_YEAR`` constant to use Gregorian year (31,556,952 seconds = 365.2425 days) for calendar consistency.

AI Assistance
-------------

- Claude Code assisted with implementing the fix for broken ``months_old`` and ``years_old`` methods in the TimeUtils refinement, including analysis, implementation, testing, and documentation.
