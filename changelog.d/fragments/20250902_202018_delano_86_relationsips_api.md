<!--
A new scriv changelog fragment.

Uncomment the section that is right (remove the HTML comment wrapper).
For top level release notes, leave all the headers commented out.
-->


### Added

- Added generate_short_id and shorten_securely from OT::Utils::SecureNumbers
- **Enhanced Feature System**: Implemented hierarchical feature registration with ancestry chain traversal
- **SafeDump DSL**: Replaced `@safe_dump_fields` with clean DSL methods (`safe_dump_field`, `safe_dump_fields`)
- **Familia::Features::Autoloader**: Added auto-loading module for project-specific features

### Feature System Improvements

The new feature system enables better organization of project-specific features:

- **Model-specific feature registration**: Classes can have their own feature registries that follow inheritance
- **Standardized feature names**: Use `deprecated_fields.rb` instead of `customer_deprecated_fields.rb`
- **Clean SafeDump DSL**: Replace brittle `@safe_dump_fields` with explicit methods
- **Automatic feature loading**: Include `Familia::Features::Autoloader` to discover features automatically

See `docs/migration/v2.0.0-pre11.md` for complete migration guide and examples.


### TODO

- external ID and object id features to add field :extid, field :objid

<!--
### Deprecated

- A bullet item for the Deprecated category.

-->
<!--
### Removed

- A bullet item for the Removed category.

-->
<!--
### Fixed

- A bullet item for the Fixed category.

-->
<!--
### Security

- A bullet item for the Security category.

-->
<!--
### Documentation

- A bullet item for the Documentation category.

-->
<!--
### AI Assistance

- A bullet item for the AI Assistance category.

-->
