Added
-----

- Feature-specific autoloader support: Features can now automatically load their own extension files from user project directories. When a feature like SafeDump is included, it searches for files matching patterns like ``{model_name}/{feature_name}_*.rb`` in the user's codebase, enabling modular feature organization.

AI Assistance
-------------

- Significant AI assistance in designing and implementing the feature-specific autoloader system, including architectural analysis, call stack debugging, and pattern matching logic for distinguishing between general and feature-specific autoloading contexts.
