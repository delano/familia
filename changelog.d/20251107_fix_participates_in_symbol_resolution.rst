.. Added
.. -----

.. Changed
.. -------

.. Deprecated
.. ----------

.. Removed
.. -------

.. Fixed
.. -----

- **Participation Relationships with Symbol/String Target Classes**: Fixed a NoMethodError that occurred when calling `participates_in` with a Symbol or String target class instead of a Class object. The error was: ``private method 'member_by_config_name' called for module Familia``.

  **Background**: The `participates_in` method supports flexible target class specifications:

  .. code-block:: ruby

     class Domain < Familia::Horreum
       # All three forms should work:
       participates_in Customer, :domains           # Class object (always worked)
       participates_in :Customer, :domains          # Symbol (was broken)
       participates_in 'Customer', :domains         # String (was broken)
     end

  **Root Cause**: The method had redundant class resolution code that directly called the private `Familia.member_by_config_name` method instead of using the public `Familia.resolve_class` API.

  **Solution**: Removed the redundant resolution code and now uses the already-resolved class from the public API, simplifying the implementation and fixing the visibility issue.

  **Impact**: Projects using Symbol or String target classes in `participates_in` declarations will now work correctly. This pattern is common when avoiding circular dependencies or when target classes are defined in different files.

.. Security
.. --------

.. Documentation
.. -------------

.. AI Assistance
.. -------------

- **Root Cause Analysis**: Claude Code analyzed the error stack trace and identified that a private method was being called as a public method from outside the Familia module.
- **Fix Implementation**: Claude Code identified redundant class resolution code and simplified it to use the already-resolved class from the public API.
- **Test Coverage**: Claude Code created comprehensive regression tests including:

  - Feature-level tests for Symbol/String target class resolution in participation relationships
  - Unit tests for the `Familia.resolve_class` public API
  - Edge case coverage for case-insensitive resolution and modularized classes
