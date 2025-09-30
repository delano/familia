.. Refactor indexing API terminology for v2.0

Changed
-------

- **BREAKING:** Renamed indexing API methods for clarity. Issue #128

  - ``class_indexed_by`` → ``unique_index`` (1:1 field-to-object mapping via HashKey)
  - ``indexed_by`` → ``multi_index`` (1:many field-to-objects mapping via UnsortedSet)
  - Parameter ``target:`` → ``within:`` for consistency across both index types

- **BREAKING:** Changed ``multi_index`` to use ``UnsortedSet`` instead of ``SortedSet``. Issue #128

  Multi-value indexes no longer include temporal scoring. This aligns with the design philosophy that indexing is for finding objects by attribute, not ordering them. Sort results in Ruby when needed: ``employees.sort_by(&:hire_date)``

Added
-----

- Added support for instance-scoped unique indexes via ``unique_index`` with ``within:`` parameter. Issue #128

  Example: ``unique_index :badge_number, :badge_index, within: Company`` creates per-company unique badge lookups using HashKey DataType.

Documentation
-------------

- Updated inline module documentation
    - ``Familia::Features::Relationships::Indexing`` with comprehensive examples, terminology guide, and design philosophy.
    - ``Familia::Features::Relationships::Participation`` to clarify differences from indexing module.

AI Assistance
-------------

- Architecture design, implementation, test updates, and documentation for indexing API refactoring completed with Claude Code assistance. Issue #128
