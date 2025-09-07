Added
-----

- Feature-specific autoloader support: Features can now automatically load their own extension files from user project directories. When a feature like SafeDump is included, it searches for files matching patterns like ``{model_name}/{feature_name}_*.rb`` in the user's codebase, enabling modular feature organization.

Changed
-------

- Refactored autoloading system: Consolidated duplicate code between ``Familia::Autoloader`` and ``Familia::Features::Autoloadable`` modules. Moved Autoloader from Features namespace to top-level Familia namespace for better separation of concerns. Both modules now share a common ``autoload_files`` method while maintaining their distinct purposes.

Fixed
-----

- Fixed autoloading thread safety issues: Eliminated shared module-level ``@calling_location`` variable that caused race conditions when multiple classes included the same feature simultaneously. Replaced with Ruby's built-in ``Module.const_source_location`` introspection for reliable per-class source location detection.
- Fixed autoloading timing issues: Moved from ``included`` hook to post-inclusion hook system, ensuring features are fully set up before extension files are loaded. This prevents incomplete feature state during autoloading.
- Improved type safety and error handling: Removed redundant type checks, added nil safety for anonymous classes, and clarified conditional ``super`` call usage throughout the autoloading system.

Documentation
-------------

- Added comprehensive YARD documentation to ``Familia::Autoloader`` and ``Familia::Features::Autoloadable`` modules, documenting their purposes, parameters, and conventional file patterns.
- Added detailed Feature System Autoloading guide (``docs/guides/Feature-System-Autoloading.md``) explaining the post-inclusion hook system, timing requirements, file naming conventions, and implementation details.

AI Assistance
-------------

- Significant AI assistance in designing and implementing the feature-specific autoloader system, including architectural analysis, call stack debugging, and pattern matching logic for distinguishing between general and feature-specific autoloading contexts.
- AI assistance in consolidating autoloader modules, identifying code duplication, designing shared interfaces, and writing YARD documentation.
- AI assistance in debugging and fixing thread safety issues, namespace collision problems, and timing-related bugs in the autoloading system. Including analysis of Ruby's introspection methods and method resolution order debugging.
