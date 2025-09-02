# changelog.d/README.md

---

# Changelog Fragments

This directory contains changelog fragments managed by [Scriv](https://scriv.readthedocs.io/).

## How to Add Changelog Entries

### Quick Start

1. **Create a new fragment:**
   ```bash
   scriv create --edit
   ```

2. **Fill in relevant sections** in the generated fragment file:
   ```markdown
   ### Added
   - New batch_indexed_by method for bulk index creation

   ### Fixed
   - Fixed race condition in connection pooling
   ```

3. **Commit with your code:**
   ```bash
   git add changelog.d/fragments/your_fragment.md
   git commit -m "Add batch_indexed_by method"
   ```

### Categories

Use these categories based on [Keep a Changelog](https://keepachangelog.com):

- **Added** - New features or capabilities
- **Changed** - Changes to existing functionality
- **Deprecated** - Soon-to-be removed features
- **Removed** - Now removed features
- **Fixed** - Bug fixes
- **Security** - Security-related improvements
- **Documentation** - Documentation improvements

### Release Process

At release time, fragments are collected into `CHANGELOG.md`:

```bash
scriv collect --version 2.0.0-pre8
```

This aggregates all fragments, updates the changelog, and removes the collected fragments.

## Fragment Guidelines

- **One fragment per feature/fix** - Keep changes focused
- **User-facing language** - Describe impact, not implementation
- **Be specific** - "Fixed connection pool race condition" vs "Fixed bug"
- **Include context** - Reference issue numbers when applicable

## References

- @see https://github.com/delano/familia/issues/84
