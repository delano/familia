# Connection Pool Stress Testing Framework

This framework provides comprehensive stress testing capabilities for the Familia connection pool implementation. It validates behavior under various threading models, load conditions, and failure scenarios.

## Quick Start

### Run a simple stress test:
```bash
cd try/prototypes
ruby connection_pool_stress_test.rb
```

### Run all threading models comparison:
```bash
ruby connection_pool_threading_models.rb
```

### Run complete test suite:
```bash
# Light testing (quick validation)
ruby run_stress_tests.rb --config light

# Moderate testing (recommended for development)
ruby run_stress_tests.rb --config moderate

# Heavy testing (thorough validation)
ruby run_stress_tests.rb --config heavy --verbose
```

## Components

### Core Framework (`connection_pool_stress_test.rb`)
- **StressTestConfig**: Configuration constants and test scenarios
- **MetricsCollector**: Basic metrics collection and CSV export
- **StressTestAccount**: Enhanced test model with complex operations
- **ConnectionPoolStressTest**: Main stress test class with multiple scenarios

**Key Scenarios**:
- `pool_starvation`: More threads than connections to test queue behavior
- `rapid_fire`: Minimal work per connection to test acquisition overhead
- `long_transactions`: Hold connections longer to test timeout behavior
- `nested_transactions`: Test transaction isolation
- `error_injection`: Test error recovery and pool stability
- `mixed_workload`: Balanced read/write/transaction operations

### Threading Models (`connection_pool_threading_models.rb`)
Tests different concurrency approaches:

- **TraditionalThreads**: Standard Ruby threads
- **FiberBased**: Cooperative concurrency using Fibers
- **ThreadPool**: Fixed worker threads with job queue
- **HybridThreadFiber**: Threads containing multiple fibers
- **ActorModel**: Message-passing concurrency pattern

### Enhanced Metrics (`connection_pool_metrics.rb`)
- **DetailedMetricsCollector**: Comprehensive metrics with percentiles
- **ResultAggregator**: Aggregates results across multiple runs
- Advanced CSV export with separate files for operations, errors, pool stats
- ASCII visualization and reporting

### Visualization (`visualize_stress_results.rb`)
- Reads CSV output from stress tests
- Generates markdown reports with ASCII charts
- Performance analysis with histograms and timelines
- Pool utilization graphs
- Error analysis and trends

### Test Runner (`run_stress_tests.rb`)
Orchestrates comprehensive testing with:
- Predefined configuration sets (light, moderate, heavy, extreme)
- Multiple threading models and operation mixes
- Automated report generation
- Executive summary with recommendations

## Configuration Options

### Threading Models
- `traditional`: Standard Ruby threads
- `fiber`: Fiber-based cooperative concurrency
- `thread_pool`: Fixed worker thread pool
- `hybrid`: Threads with nested fibers
- `actor`: Simplified actor model

### Operation Mixes
- `balanced`: 33% read, 33% write, 34% transaction
- `read_heavy`: 80% read, 15% write, 5% transaction
- `write_heavy`: 20% read, 70% write, 10% transaction
- `transaction_heavy`: 10% read, 20% write, 70% transaction

### Test Scenarios
- `pool_starvation`: Test behavior when pool is exhausted
- `rapid_fire`: High-frequency, short-duration operations
- `long_transactions`: Operations that hold connections longer
- `nested_transactions`: Test transaction isolation and nesting
- `error_injection`: Test error recovery and stability
- `mixed_workload`: Realistic mixed operation patterns

## Understanding Results

### Key Metrics
- **Success Rate**: Percentage of operations that completed successfully
- **Avg Duration**: Average time per operation (in seconds)
- **Avg Wait Time**: Average time waiting for connection (in seconds)
- **Max Pool Utilization**: Peak percentage of pool connections in use
- **Error Rates**: Breakdown of failures by type

### CSV Output Files
- `*_operations_*.csv`: Individual operation details
- `*_errors_*.csv`: Error details and context
- `*_pool_stats_*.csv`: Pool utilization over time
- `*_summary_*.csv`: Aggregated metrics
- `comparison_results.csv`: Cross-configuration comparison

### Interpreting Results

**Good Performance Indicators**:
- Success rate > 99%
- Connection wait times < 100ms
- Pool utilization stays reasonable (< 80% for most of the test)
- Consistent performance across operation types

**Warning Signs**:
- Success rate < 95%
- High connection wait times (> 1 second)
- Pool utilization consistently > 90%
- High error rates or timeouts

**Failure Modes**:
- Pool exhaustion: Many threads waiting for connections
- Deadlock: Operations hang indefinitely
- Connection leaks: Pool size effectively shrinks over time
- Cascading failures: Errors cause more errors

## Customization

### Adding New Threading Models
1. Extend `ThreadingModels::BaseModel`
2. Implement the `run` method
3. Add to factory method in `ThreadingModels.create`

### Adding New Scenarios
1. Add scenario to `StressTestConfig::SCENARIOS`
2. Implement handler method in `ConnectionPoolStressTest`
3. Add to scenario selection logic

### Custom Metrics
1. Extend `MetricsCollector` or `DetailedMetricsCollector`
2. Add new metric recording methods
3. Update summary and export methods

## Examples

### Quick Pool Starvation Test
```ruby
test = ConnectionPoolStressTest.new(
  thread_count: 20,      # More than pool size
  pool_size: 10,         # Smaller pool
  operations_per_thread: 50,
  scenario: :pool_starvation
)
test.run
```

### Compare Threading Models
```ruby
test = EnhancedConnectionPoolStressTest.new(
  thread_count: 50,
  operations_per_thread: 100,
  pool_size: 20
)
results = test.compare_all_models
```

### Generate Visualization
```bash
# After running tests that generate CSV files
./visualize_stress_results.rb *.csv > report.md
```

## Troubleshooting

### Common Issues
1. **"Redis connection refused"**: Make sure Redis is running
2. **"Pool timeout"**: Increase pool timeout or reduce thread count
3. **High memory usage**: Reduce operations per thread or use smaller pool
4. **CSV files not found**: Check that tests completed successfully

### Debug Mode
```ruby
Familia.debug = true
test = ConnectionPoolStressTest.new(verbose: true)
test.run
```

### Performance Tuning
- Start with `light` configuration for initial validation
- Use `moderate` for regular development testing
- Reserve `heavy` and `extreme` for comprehensive validation
- Monitor system resources during testing
- Consider Redis configuration (memory, connections, timeouts)
