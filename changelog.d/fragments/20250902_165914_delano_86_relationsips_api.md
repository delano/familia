### Changed
- **BREAKING**: Refactored Familia Relationships API to remove "global" terminology and simplify method generation. (Closes #86)
- Split `generate_indexing_instance_methods` into focused `generate_direct_index_methods` and `generate_relationship_index_methods` for better separation between direct class-level and relationship-based indexing.
- Simplified method generation by removing complex global vs parent conditionals.
- All indexes are now stored at the class level for consistency.

### Added
- Automatic indexing and class-level tracking on `save()` operations, eliminating the need for manual index updates.
- Enhanced collection syntax supports the Ruby-idiomatic `<<` operator for more natural relationship management.

### Fixed
- Method generation now works consistently for both `class_indexed_by` and `indexed_by` with a `parent:`.
- Resolved metadata storage issues for dynamically created classes.
- Improved error handling for nil class names in tracking relationships.

### AI Assistance
- This refactoring was implemented with Claude Code assistance, including comprehensive test updates and API modernization.
