Fixed
-----

- Fixed serialization mismatch in relationships module where extracting
  ``.identifier`` before passing to DataType methods caused cross-path lookup
  failures. Items added via relationships couldn't be found via direct DataType
  access because ``serialize_value(object)`` extracts raw identifiers while
  ``serialize_value(string)`` JSON-encodes them. Now passes Familia objects
  directly to DataType methods. (`#212 <https://github.com/delano/familia/issues/212>`_)

Added
-----

- Added ``serialization_consistency_try.rb`` regression tests verifying that
  object-based lookups work consistently across relationships module and direct
  DataType access for sorted sets, unsorted sets, and lists.

Documentation
-------------

- Documented known limitation: string identifier lookups get JSON-encoded by
  design. Always use Familia objects instead of raw string identifiers for
  DataType operations like ``member?()``, ``score()``, and ``remove()``.

AI Assistance
-------------

- Claude assisted with root cause analysis of the serialization mismatch,
  identifying the 7 occurrences in ``collection_operations.rb`` where
  ``.identifier`` extraction needed to be removed, and writing comprehensive
  regression tests covering all three collection types.
