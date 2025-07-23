# Connection Pool Stress Testing

## Quick Start
```bash
# Basic stress test
ruby run_stress_tests.rb --config light

# Full comparison
ruby configurable_stress_test.rb --ci
```

## Documentation
- [Basic Usage](docs/README_stress_testing.md)
- [Advanced Configuration](docs/README_advanced_usage.md)

## Structure
- `run_stress_tests.rb` - Main test orchestrator
- `configurable_stress_test.rb` - Configurable test runner
- `lib/` - Core testing libraries
- `docs/` - Documentation
