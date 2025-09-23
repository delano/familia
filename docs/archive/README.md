# Archived Documentation

This directory contains original documentation files that have either been migrated to the new Scriv-based changelog system or incorporated into other documents.

## Migration Date
**Sept 22, 1015** - Deprecated api-reference.md, to reduce surface area for stale documentation to hide.
**Sept 1, 2025** - As part of implementing [Issue #84: Scriv-based changelog system](https://github.com/delano/familia/issues/84)

## Archived Files

### FAMILIA_UPDATE.md
**Original Purpose:** Version summary table and detailed release notes for v2.0.0-pre series

**Migrating Destinations:**
- **Changelog entries** → Extracted to Scriv fragments, aggregated into `CHANGELOG.md`
- **Migrating guides** → Reorganized into `docs/migrating/v2.0.0-pre*.md`
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
├── migrating/              # Version-specific migrating guides
│   ├── v2.0.0-pre.md
│   ├── v2.0.0-pre5.md      # Security features
│   ├── v2.0.0-pre6.md      # Architecture improvements
│   └── v2.0.0-pre7.md      # Relationships system
│
├── guides/                 # Feature-specific guides (moved from wiki/)
│   ├── relationships.md    # From FAMILIA_RELATIONSHIPS.md
│   └── [other guides...]
│
├── reference/              # Technical reference
│   └── api-technical.md
│
└── archive/                # This directory
```

## Finding Migrated Content

- **Version changes** → Check `CHANGELOG.md` (generated from fragments)
- **How to upgrade** → See `docs/migration/` for version-specific guides
- **Feature usage** → See `docs/guides/` for implementation examples
- **API reference** → See `docs/reference/` for technical details

## References

- [Issue #84](https://github.com/delano/familia/issues/84) - Original migration plan
- [Scriv Documentation](https://scriv.readthedocs.io/) - Changelog management tool
- [Keep a Changelog](https://keepachangelog.com/) - Changelog format standard
