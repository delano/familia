# Changelog Fragments

This directory contains changelog fragments managed by [Scriv](https://scriv.readthedocs.io/).

## Our Approach

Changelogs are for humans and agents, not just machines. We follow the core principles of [Keep a Changelog](https://keepachangelog.com) to ensure our release notes are clear, consistent, and trustworthy.

To achieve this, we use a fragment-based workflow with `scriv`. Instead of a single, large `CHANGELOG.md` file that can cause merge conflicts, each developer includes a small changelog fragment with their pull request. At release time, these fragments are collected and aggregated into the main changelog.

This approach provides several benefits:
- **Reduces Merge Conflicts:** Developers can work in parallel without conflicting over a central changelog file.
- **Improves Developer Experience:** Creating a small, focused fragment is a simple and repeatable task during development.
- **Ensures Consistency:** Automation helps maintain a consistent structure for all changelog entries.
- **Builds Trust:** A clear and well-maintained changelog communicates respect for our users and collaborators.

## How to Add a Changelog Entry

1.  **Create a New Fragment:**
    ```bash
    scriv create
    ```
    This will create a new file in the `changelog.d/fragments/` directory.

2.  **Edit the Fragment File:**
    Open the newly created file and add your entry under the relevant category. See the guidelines below for writing good entries.

3.  **Commit with Your Code:**
    ```bash
    git add changelog.d/fragments/your_fragment_name.md
    git commit
    ```

## Fragment Guidelines

-   **One Fragment Per Change:** Keep each fragment focused on a single feature, fix, or improvement.
-   **Documenting AI Assistance:** If a change involved significant AI assistance, place it in its own fragment. This ensures the `### AI Assistance` section clearly corresponds to the single change described in that fragment.
-   **Write for a Human Audience:** Describe the *impact* of the change, not just the implementation details.
    -   **Good:** "Improved the performance and stability of Redis connections under high load."
    -   **Bad:** "Refactored the `RedisManager` to use a connection pool."
-   **Be Specific:** Avoid generic messages like "fixed a bug." Clearly state what was fixed.
-   **Include Context:** Reference issue or pull request numbers to provide a link to the discussion and implementation details. `scriv` will automatically create links for them.
    -   **Example:** `- Fixed a bug where users could not reset their passwords. (Closes #123)`

### Categories

Use these categories from [Keep a Changelog](https://keepachangelog.com):

-   **Added**: New features or capabilities.
-   **Changed**: Changes to existing functionality.
-   **Deprecated**: Soon-to-be removed features.
-   **Removed**: Now removed features.
-   **Fixed**: Bug fixes.
-   **Security**: Security-related improvements.
-   **Documentation**: Documentation improvements.

## Release Process

At release time, an authorized maintainer will collect all fragments into the main `CHANGELOG.md` file:

```bash
scriv collect --version 1.2.3
```
