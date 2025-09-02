# Archived Documentation

This directory contains original documentation files that have been migrated to the new Scriv-based changelog system and reorganized documentation structure.

## Migration Date
**September 1, 2025** - As part of implementing [Issue #84: Scriv-based changelog system](https://github.com/delano/familia/issues/84)

## Archived Files

### FAMILIA_UPDATE.md
**Original Purpose:** Version summary table and detailed release notes for v2.0.0-pre series

**Migration Destinations:**
- **Changelog entries** → Extracted to Scriv fragments, aggregated into `CHANGELOG.md`
- **Migration guides** → Reorganized into `docs/migration/v2.0.0-pre*.md`
- **Feature descriptions** → Cross-referenced with existing feature guides in `docs/guides/`

### FAMILIA_RELATIONSHIPS.md
**Original Purpose:** Auto-generated relationship methods reference

**Migration Destination:**
- **Complete content** → Moved to `docs/guides/relationships-methods.md`
- **Cross-referenced** with existing `docs/guides/Relationships-Guide.md`

### FAMILIA_TECHNICAL.md
**Original Purpose:** Technical API reference for v2.0.0-pre series classes and methods

**Migration Destination:**
- **Core technical content** → Moved to `docs/reference/api-technical.md`
- **Cross-referenced** with existing `docs/guides/API-Reference.md`

## New Documentation Structure

```
docs/
├── migration/           # Version-specific migration guides
│   ├── v2.0.0-pre.md   # Foundation migration
│   ├── v2.0.0-pre5.md  # Security features
│   ├── v2.0.0-pre6.md  # Architecture improvements
│   └── v2.0.0-pre7.md  # Relationships system
├── guides/              # Feature guides (moved from wiki/)
│   ├── relationships-methods.md  # From FAMILIA_RELATIONSHIPS.md
│   └── [other guides...]
├── reference/           # Technical reference
│   └── api-technical.md # From FAMILIA_TECHNICAL.md
└── archive/            # This directory
```

## Why These Files Were Archived

1. **Sustainability** - The original files accumulated overlapping content without clear organization
2. **Maintainability** - Scriv fragment system prevents documentation bloat
3. **Clarity** - Separation of changelog, guides, and reference improves findability
4. **Workflow** - Fragment-based workflow scales better with development

## Finding Migrated Content

- **Version changes** → Check `CHANGELOG.md` (generated from fragments)
- **How to upgrade** → See `docs/migration/` for version-specific guides
- **Feature usage** → See `docs/guides/` for implementation examples
- **API reference** → See `docs/reference/` for technical details

## References

- [Issue #84](https://github.com/delano/familia/issues/84) - Original migration plan
- [Scriv Documentation](https://scriv.readthedocs.io/) - Changelog management tool
- [Keep a Changelog](https://keepachangelog.com/) - Changelog format standard
