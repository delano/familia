Added
-----

- **Feature-specific autoloading**: Features can now automatically discover and load extension files from your project directories. When you include a feature like ``safe_dump``, Familia searches for configuration files using conventional patterns like ``{model_name}/{feature_name}_*.rb``, enabling clean separation between core model definitions and feature-specific configurations.

- **Consolidated autoloader architecture**: Introduced ``Familia::Autoloader`` as a shared utility for consistent file loading patterns across the framework, supporting both general-purpose and feature-specific autoloading scenarios.

Documentation
-------------

- **Feature System Autoloading Guide**: Added comprehensive guide at ``docs/guides/Feature-System-Autoloading.md`` explaining the new autoloading system, including file naming conventions, directory patterns, and usage examples.
- **Enhanced API documentation**: Added detailed YARD documentation for autoloading modules and methods.

AI Assistance
-------------

- Significant AI assistance in architectural design and implementation of the feature-specific autoloading system, including pattern matching logic, Ruby introspection methods, and comprehensive debugging of edge cases and thread safety considerations.
