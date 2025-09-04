# Changelog Fragments

This directory contains changelog fragments managed by [Scriv](https://scriv.readthedocs.io/).

## Our Approach

Changelogs are for humans and agents, not just machines. We follow the core principles of [Keep a Changelog](https://keepachangelog.com) and semvar to ensure our release notes are clear, consistent, and useful.

To achieve this, we use a fragment-based workflow with `scriv`. Instead of a single, large `CHANGELOG.md` file that can cause merge conflicts, each developer includes a small changelog fragment with their pull request. At release time, these fragments are collected and aggregated into the main changelog.

This approach provides several benefits:
- **Reduces Merge Conflicts:** Developers can work in parallel without conflicting over a central changelog file.
- **Improves Developer Experience:** Creating a small, focused fragment is a simple and repeatable task during development.
- **Ensures Consistency:** Automation helps maintain a consistent structure for all changelog entries.
- **AI Transparency:** An opportunity to be specific and detailed about the assistance provided.
- **Builds Trust:** A clear and well-maintained changelog communicates respect for our users and collaborators.

## Relevant paths

* `changelog.d/` - (e.g. changelog.d/YYYYMMDD_HHmmss_username_branch.md)
* `docs/migrating/` - (e.g. docs/migrating/v2.0.0-pre.md)
* `CHANGELOG.md` - The full changelog for all releases, in reverse chronological order. Careful: LARGE DOCUMENT. Limit reading to the first 50 lines.

* `setup.cfg` - Scriv tool settings

## How to Add a Changelog Entry

1.  **Create a New Fragment:**

```bash
# This will create a new file in the `changelog.d/` directory.
scriv create
```

2.  **Edit the Fragment File:**
Open the newly created file and add your entry under the relevant category. See the guidelines below for writing good CHANGELOG entries.

3. **Add or Update Migrating Guide:** (optional)
Include technical details to help developers update to the new version. Start with a specific introduction, e.g. "This version introduces significant improvements to Familia's feature system, making it easier to organize and use features across complex projects.". Including code snippets and multi-line content that is too detailed for the CHANGELOG.

Use the content of an existing `docs/migrating/vMajor.Minor.Patch*.md file as a reference.

Compare the headers of your draft content with the headers of the previous migration guide to make sure it does not repeat or overlap.

4.  **Commit with Your Code:**
```bash
git add changelog.d/YYYYMMDD_HHmmss_username_branch.md [docs/migrating/v2.0.0-pre.md]
git commit
```

## Fragment Guidelines

- **One Fragment Per Change:** Keep each fragment focused on a single feature, fix, or improvement.
- **Documenting AI Assistance:** If a change involved significant AI assistance, place it in its own fragment. This ensures the `### AI Assistance` section clearly corresponds to the single change described in that fragment.
- **Write for a Human Audience:** Describe the *impact* of the change, not just the implementation details.
    - **Good:** "Improved the performance and stability of Redis connections under high load."
    - **Bad:** "Refactored the `RedisManager`."
- **Be Specific:** Avoid generic messages like "fixed a bug." Clearly state what was fixed.
- **Include Context:** Reference issue or pull request numbers to provide a link to the discussion and implementation details. `scriv` will automatically create links for them.
    - **Example:** `- Fixed a bug where users could not reset their passwords. PR #123`

### Categories

Use these categories:

- **Added**: New features or capabilities.
- **Changed**: Changes to existing functionality.
- **Deprecated**: Soon-to-be removed features.
- **Removed**: Now removed features.
- **Fixed**: Bug fixes.
- **Security**: Security-related improvements.
- **Documentation**: Documentation improvements.
- **AI Assistance**: Significant AI assistance in the change, including discussion, rubber ducking, formatting, writing documentation, writing tests.

## Release Process

At release time, scriv will collect all fragments into the main `CHANGELOG.md` file with th command `scriv collect`. The version is taken automatically from `lib/familia/version.rb`.
