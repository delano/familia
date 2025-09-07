Added
-----

- Feature-specific autoloader support: Features can now automatically load their own extension files from user project directories. When a feature like SafeDump is included, it searches for files matching patterns like ``{model_name}/{feature_name}_*.rb`` in the user's codebase, enabling modular feature organization.

Changed
-------

- Refactored autoloading system: Consolidated duplicate code between ``Familia::Autoloader`` and ``Familia::Features::Autoloadable`` modules. Moved Autoloader from Features namespace to top-level Familia namespace for better separation of concerns. Both modules now share a common ``autoload_files`` method while maintaining their distinct purposes.

Documentation
-------------

- Added comprehensive YARD documentation to ``Familia::Autoloader`` and ``Familia::Features::Autoloadable`` modules, documenting their purposes, parameters, and conventional file patterns.

AI Assistance
-------------

- Significant AI assistance in designing and implementing the feature-specific autoloader system, including architectural analysis, call stack debugging, and pattern matching logic for distinguishing between general and feature-specific autoloading contexts.
- AI assistance in consolidating autoloader modules, identifying code duplication, designing shared interfaces, and writing YARD documentation.
