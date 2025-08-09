# Familia Encryption Debugging Tools

Debug scripts for encryption issues. All scripts run safely without modifying data.

## Quick Reference

| Issue | Script | Purpose |
|-------|--------|---------|
| Provider problems | `provider_diagnostics.rb` | Test provider registration, availability, compatibility |
| Performance issues | `cache_behavior_tracer.rb` | Analyze key derivation cache efficiency |
| Field operations | `encryption_method_tracer.rb` | Trace encrypt/decrypt calls with timing |

```bash
# Run any script
ruby try/debugging/[script_name].rb
```

## Usage Guide

**Provider Issues**: Algorithm not found, registration failures
→ `provider_diagnostics.rb`

**Slow Performance**: Excessive key derivations, cache misses
→ `cache_behavior_tracer.rb` then `encryption_method_tracer.rb`

**Field Bugs**: AAD problems, context issues, decryption failures
→ `encryption_method_tracer.rb`

## Output Key
- **SUCCESS/FAILED/ERROR** = test results
- `version:context => [bytes]` = cache entries
- Timing in milliseconds = performance data
