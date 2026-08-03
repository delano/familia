# Changelog Fragments

This directory contains changelog fragments managed by [Scriv](https://scriv.readthedocs.io/).

## Our Approach

Changelogs are for humans and agents, not just machines. We follow [Keep a Changelog](https://keepachangelog.com) and semver to ensure clear, consistent, and useful release notes.

We use a fragment-based workflow with `scriv`. Each developer includes a small, focused changelog fragment with their pull request. At release time, these are compiled into the main changelog.

Benefits:
- **No Merge Conflicts:** Developers work in parallel without conflicting over a single file.
- **Improved DX:** Creating a small fragment is simple and repeatable.
- **AI Transparency:** Briefly notes AI involvement without cluttering technical sections.
- **Consistency:** Automation maintains a unified structure.

### Relevant Paths

* `changelog.d/` - Fragment directory (e.g. `changelog.d/YYYYMMDD_HHmmss_username_branch.rst`)
* `docs/migrating/` - Migration guides (e.g. `docs/migrating/v2.0.0-pre.md`)
* `CHANGELOG.rst` - The full changelog (reverse chronological, large file; read only the top 100 lines default)
* `changelog.d/scriv.ini` - Scriv configuration

## Add a Changelog Entry

1. **Create a New Fragment:**
   ```bash
   scriv create
   ```
2. **Edit the Fragment:**
   Open the new `.rst` file and write your entry under the relevant category using the guidelines below.
3. **Add or Update Migrating Guide (Optional):**
   If the change requires developer action to upgrade, add or update a guide in `docs/migrating/`. Use existing guides as a reference and ensure headers do not repeat.
4. **Commit with Your Code:**
   ```bash
   git add changelog.d/YYYYMMDD_HHmmss_username_branch.rst [docs/migrating/v2.0.0-pre.md]
   git commit
   ```

## Fragment Guidelines

- **One Fragment Per Change:** Keep each fragment focused on a single feature, fix, or improvement.
- **Reference Context:** Include issue or PR numbers. Scriv will automatically link them. (e.g., `PR #123`).

## Content Guidelines

- **Target the Consumer:** Focus exclusively on external, breaking, or actionable behavior. Omit internal implementation steps, development metadata, and agent logs.
- **Impact-Driven Filtering:** Focus strictly on technical facts (method/class signatures, parameters, exceptions, issues resolved) and eliminate explanatory "how" or "why" narratives.
  - **Good:** "Added ``Familia::HashKey#claim_field`` and ``#release_field`` for single-hash server-side CAS/CAD operations. Raises ``Familia::OperationModeError`` in pipelines/transactions."
  - **Bad:** "We found a race condition during an audit, so we added a nice compare-and-set wrapper called `#claim_field` to allow callers to safely claim a field in single hash fields."
- **Process Log Exclusion:** Remove all development metadata (such as tool-specific implementation notes, agent logs, and audit timelines) that do not change library APIs or behavior.
- **Maintain Consistency:** Match the terse style, semantic classification, and spacing of previous changelog versions.

## Categories

Use these standard headers in your fragment:

- **Added**: New features or capabilities.
- **Changed**: Changes to existing functionality.
- **Deprecated**: Soon-to-be removed features.
- **Removed**: Now removed features.
- **Fixed**: Bug fixes.
- **Security**: Security-related improvements.
- **Documentation**: Documentation improvements.
- **AI Assistance**: Terse, single-sentence acknowledgment of AI assistance for the change. Do not duplicate technical details already listed in other categories.

## Release Process

At release, run `scriv collect` to aggregate all fragments into `CHANGELOG.rst`. The version is parsed automatically from `lib/familia/version.rb`.
