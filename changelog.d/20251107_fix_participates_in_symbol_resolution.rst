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

- **Participation Relationships with Symbol/String Target Classes**: Fixed four bugs that occurred when calling `participates_in` with a Symbol or String target class instead of a Class object.

  **Bug 1 - NoMethodError during relationship definition**:

  The error was: ``private method 'member_by_config_name' called for module Familia``.

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

  **Bug 2 - NoMethodError in current_participations**:

  When calling `current_participations` on objects that used Symbol/String target classes, it would fail with ``undefined method 'familia_name' for Symbol``.

  **Root Cause**: The `current_participations` method was calling `.familia_name` on `config.target_class`, which stores the original Symbol/String value passed to `participates_in`.

  **Solution**: Use the resolved `target_class` variable instead of the stored config value. The resolved class is already available from the `Familia.resolve_class` call earlier in the method.

  **Bug 3 - NoMethodError in target_class_config_name**:

  When calling `current_participations`, the internal `target_class_config_name` method would fail with ``undefined method 'config_name' for Symbol``.

  **Root Cause**: The `ParticipationRelationship.target_class_config_name` method was calling `.config_name` directly on the stored `target_class` value, which could be a Symbol or String.

  **Solution**: Resolve the target class before calling `config_name` by using `Familia.resolve_class(target_class)`, which handles all input types (Class, Symbol, String) correctly.

  **Bug 4 - Confusing error when target class not loaded**:

  When the target class hasn't been loaded yet (load order issue), the error was: ``undefined method 'method_defined?' for nil``.

  **Root Cause**: When `Familia.resolve_class` returns `nil` (because the target class isn't registered in `Familia.members` yet), the code would pass `nil` to `TargetMethods::Builder.build`, which then failed with a confusing error message that didn't explain the actual problem.

  **Solution**: Added explicit nil check after `resolve_class` with a detailed ArgumentError that:

  - Clearly states which target class couldn't be resolved
  - Lists the three most common causes (load order, typo, not inheriting from Horreum)
  - Shows all currently registered Familia classes for debugging
  - Provides a clear solution for fixing the load order

  **Impact**: Projects using Symbol or String target classes in `participates_in` declarations will now work correctly throughout the entire lifecycle, including relationship definition, method generation, and participation queries. When there's a load order issue or typo, developers get a clear, actionable error message instead of a confusing nil error. This pattern is common when avoiding circular dependencies or when target classes are defined in different files.

.. Security
.. --------

.. Documentation
.. -------------

.. AI Assistance
.. -------------

- **Root Cause Analysis**: Claude Code analyzed the error stack trace from the implementing project and identified that a private method was being called as a public method from outside the Familia module.
- **Fix Implementation**: Claude Code identified redundant class resolution code and simplified it to use the already-resolved class from the public API.
- **Test Coverage**: Claude Code created comprehensive regression tests including:

  - Feature-level tests for Symbol/String target class resolution in participation relationships
  - Unit tests for the `Familia.resolve_class` public API
  - Edge case coverage for case-insensitive resolution and modularized classes

- **Second Bug Discovery**: During test execution, Claude Code discovered a related bug in `current_participations` that was also failing with Symbol/String target classes. The test coverage revealed that `.familia_name` was being called on the unresolved config value instead of the resolved class instance.

- **Third Bug Discovery**: Further test execution revealed another Symbol/String bug in `target_class_config_name`, where `.config_name` was being called directly on Symbol/String values. This was fixed by resolving the class first using `Familia.resolve_class`.

- **Test Coverage Refinement**: Claude Code identified and removed unrealistic test cases (all-uppercase, all-lowercase class names) that don't occur in real Ruby code and don't work with the `snake_case` method's design. Updated tests to focus on realistic naming conventions: PascalCase and snake_case, with clear documentation explaining why certain formats aren't supported.

- **Fourth Bug Discovery**: After merging to main, the implementing project revealed a load order issue where `Familia.resolve_class` returned `nil`, causing a confusing "undefined method for nil" error. Claude Code added explicit error handling with a detailed, actionable error message that helps developers quickly identify and fix load order issues, typos, or inheritance problems.
