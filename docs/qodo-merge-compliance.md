# Qodo Merge Compliance Configuration

This document describes the Qodo Merge (formerly PR-Agent) configuration for the Familia project.

## Overview

Qodo Merge provides automated PR analysis, code reviews, and compliance checks. Our configuration enables two key compliance features:

1. **Codebase Duplication Compliance** - Uses RAG (Retrieval-Augmented Generation) to check for duplicate code across related repositories
2. **Custom Compliance** - Project-specific rules tailored to Familia's development practices

## Configuration Files

### pr_agent.toml

The main Qodo Merge configuration file located in the repository root. It includes:

- **Response Language**: Set to English for consistency
- **RAG Context Enrichment**: Enabled with related repositories (`delano/familia`, `delano/tryouts`, `delano/otto`)
- **Custom Compliance Path**: References our custom compliance checklist
- **Ignore Rules**: Excludes generated files and build artifacts from analysis

### pr_compliance_checklist.yaml

Custom compliance rules specific to Familia development:

#### ErrorHandling
All external API calls and database operations must have proper error handling with try-catch blocks or appropriate error handling mechanisms.

#### TestCoverage
New features must include tests using the Tryouts framework. Test files should be in the `try/` directory following the `*_try.rb` or `*.try.rb` naming convention.

#### ChangelogFragment
User-facing changes must include a changelog fragment in the `changelog.d/` directory following RST format, or provide explicit justification for omission.

#### DocumentationUpdates
API changes must be reflected in documentation, including YARD comments for new public methods or updates to the `docs/` directory.

#### BackwardCompatibility
Changes must maintain backward compatibility or document breaking changes in migration guides with deprecation warnings.

#### ThreadSafety
Code handling shared state must be thread-safe with proper synchronization or clear documentation of thread-safety assumptions.

#### DatabaseKeyNaming
Database key generation must follow Familia conventions:
- Use the configured `delim` separator (default `:`)
- Avoid reserved keywords: `ttl`, `db`, `valkey`, `redis`
- Handle empty identifiers to prevent stack overflow

## Interactive Commands

Team members can trigger on-demand Qodo Merge analysis in PR comments:

- `/analyze --review` - Run code review
- `/analyze --test` - Generate test suggestions
- `/improve` - Get improvement suggestions
- `/ask` - Ask questions about the PR

## Compliance Status

In PR comments from `@qodo-merge-pro`, you'll see:

- 🟢 Green circle - Compliance check passed
- 🔴 Red circle - Compliance check failed with details
- ⚪ White circle - Compliance check not configured (should not appear with proper configuration)

## References

- [Qodo Merge Configuration Options](https://qodo-merge-docs.qodo.ai/usage-guide/configuration_options/)
- [RAG Context Enrichment Guide](https://qodo-merge-docs.qodo.ai/core-abilities/rag_context_enrichment/)
- [Compliance Guide](https://qodo-merge-docs.qodo.ai/tools/compliance/)
- [Best Practices](https://docs.qodo.ai/qodo-documentation/qodo-merge/features/best-practices)

## Maintenance

### Updating Compliance Rules

To add or modify compliance rules:

1. Edit `pr_compliance_checklist.yaml`
2. Ensure YAML syntax is valid: `ruby -r yaml -e "YAML.load_file('pr_compliance_checklist.yaml')"`
3. Commit changes - they take effect immediately on new PRs

### Updating Ignore Rules

To exclude additional files from analysis:

1. Edit the `[ignore]` section in `pr_agent.toml`
2. Use glob patterns to match file paths
3. Test with new PRs to verify exclusions work as expected

## Future Improvements (Optional)

- **Centralized Configuration**: Create a `pr-agent-settings` repository with `metadata.yaml` to share configuration across all repos
- **Wiki Configuration**: Enable repo wiki and create `.pr_agent.toml` page (wiki config takes precedence over local files)
