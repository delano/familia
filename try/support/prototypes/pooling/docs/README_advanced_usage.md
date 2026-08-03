# Advanced Usage Guide - StressTestConfig & Configurable Testing

This guide demonstrates how to make effective use of the enhanced `StressTestConfig` system for systematic connection pool testing.

## Table of Contents

1. [Quick Start with Smart Configurations](#quick-start-with-smart-configurations)
2. [Systematic Testing Approaches](#systematic-testing-approaches)
3. [Environment-Based Configuration](#environment-based-configuration)
4. [Configuration Validation](#configuration-validation)
5. [Practical Examples](#practical-examples)
6. [Integration with CI/CD](#integration-with-cicd)
7. [Performance Analysis Workflows](#performance-analysis-workflows)

## Quick Start with Smart Configurations

### Development Testing (Fast Feedback)
```bash
# Quick development validation - minimal configs for fast feedback
ruby configurable_stress_test.rb --development
# Or
ruby run_stress_tests.rb --config light --verbose
```

### CI/CD Testing (Balanced Coverage)
```bash
# Comprehensive but time-bounded testing for CI
ruby configurable_stress_test.rb --ci
# Or
ruby run_stress_tests.rb --config moderate
```

### Production Validation (Comprehensive)
```bash
# Thorough testing before production deployment
ruby configurable_stress_test.rb --production
# Or
ruby run_stress_tests.rb --config heavy --verbose
```

### Performance Bottleneck Analysis
```bash
# Focus on high-stress scenarios to find limits
ruby run_stress_tests.rb --config extreme
```

## Systematic Testing Approaches

### 1. Thread Scaling Analysis

Find optimal thread-to-pool ratios:

```bash
# Test how performance scales with thread count
ruby configurable_stress_test.rb --scope thread_scaling
```

**Use Case**: Determining how many threads your application can effectively support.

**Analysis**: Look for the point where success rate drops or wait times spike.

### 2. Pool Sizing Optimization

Determine optimal pool sizes:

```bash
# Test different pool sizes under consistent load
ruby configurable_stress_test.rb --scope pool_sizing
```

**Use Case**: Right-sizing your connection pool for cost vs. performance balance.

**Analysis**: Find the minimum pool size that maintains high success rates.

### 3. Operation Mix Impact

Understand how different workload patterns affect performance:

```bash
# Test read-heavy vs write-heavy vs transaction-heavy workloads
ruby configurable_stress_test.rb --scope operation_mixes
```

**Use Case**: Optimizing for your application's specific usage patterns.

**Analysis**: Identify which operation types are bottlenecks.

### 4. Timeout Behavior Analysis

Test timeout configurations:

```bash
# Test different timeout values under high contention
ruby configurable_stress_test.rb --scope timeout_behavior
```

**Use Case**: Setting appropriate timeouts that balance responsiveness with reliability.

**Analysis**: Find timeouts that catch real issues without false positives.

## Environment-Based Configuration

### Using Environment Variables

Set up dynamic test configurations:

```bash
# Basic environment configuration
export STRESS_THREADS=10,50,100
export STRESS_POOLS=5,20
export STRESS_SCENARIOS=pool_starvation,mixed_workload

# Run with environment config
ruby run_stress_tests.rb --runtime-config --verbose
```

### Complete Environment Setup

```bash
# Comprehensive environment configuration
export STRESS_THREADS=20,50,100,200
export STRESS_OPS=100,500
export STRESS_POOLS=10,25,50
export STRESS_TIMEOUTS=5,15,30
export STRESS_SCENARIOS=pool_starvation,rapid_fire,long_transactions
export STRESS_MIXES=balanced,transaction_heavy

ruby run_stress_tests.rb --runtime-config
```

### Docker/Container Integration

```dockerfile
# Dockerfile example
FROM ruby:3.2
# ... setup code ...

ENV STRESS_THREADS=20,50
ENV STRESS_POOLS=10,20
ENV STRESS_SCENARIOS=mixed_workload,rapid_fire

CMD ["ruby", "run_stress_tests.rb", "--runtime-config"]
```

## Configuration Validation

### Validate Before Running

```bash
# Check configuration without running tests
ruby run_stress_tests.rb --config extreme --validate-config
```

### Programmatic Validation

```ruby
# In your code
config = {
  thread_count: 200,
  pool_size: 5,    # This will trigger warnings
  operations_per_thread: 2000  # This will trigger warnings
}

validation = StressTestConfig.validate_config(config)
puts "Warnings: #{validation[:warnings].join('; ')}" if validation[:warnings].any?
puts "Errors: #{validation[:errors].join('; ')}" if validation[:errors].any?
```

### Safe Configuration Merging

```ruby
# Merge configurations with validation
base_config = StressTestConfig.default
custom_overrides = { thread_count: 100, pool_size: 10 }

# This will validate and warn about potential issues
final_config = StressTestConfig.merge_and_validate(base_config, custom_overrides)
```

## Practical Examples

### Example 1: Find Your App's Threading Sweet Spot

```bash
#!/bin/bash
# find_threading_sweet_spot.sh

echo "Finding optimal thread count for your application..."

# Test thread scaling
ruby configurable_stress_test.rb --scope thread_scaling --quiet > thread_results.csv

# Analyze results
echo "Thread scaling results:"
ruby visualize_stress_results.rb thread_results.csv | grep "Thread Scaling Insights" -A 10
```

### Example 2: Pre-deployment Validation

```bash
#!/bin/bash
# pre_deployment_check.sh

echo "Running pre-deployment connection pool validation..."

# Test production-like configuration
ruby run_stress_tests.rb --config heavy --no-visualizations

# Check for any failures
if [ $? -eq 0 ]; then
    echo "✅ Connection pool validation passed - safe to deploy"
    exit 0
else
    echo "❌ Connection pool validation failed - do not deploy"
    exit 1
fi
```

### Example 3: Performance Regression Testing

```ruby
# performance_regression_test.rb
require_relative 'configurable_stress_test'

# Baseline performance test
baseline_config = StressTestConfig.merge_and_validate(
  StressTestConfig.default,
  {
    thread_count: 50,
    pool_size: 20,
    operations_per_thread: 200,
    scenario: :mixed_workload
  }
)

puts "Running baseline performance test..."
test = ConfigurableStressTest.new
result = test.run_single_config(baseline_config)

baseline_success_rate = result[:summary][:success_rate]
baseline_avg_duration = result[:summary][:avg_duration]

puts "Baseline: #{baseline_success_rate}% success, #{(baseline_avg_duration * 1000).round(2)}ms avg"

# Compare with new implementation
# (after code changes)
new_result = test.run_single_config(baseline_config)
new_success_rate = new_result[:summary][:success_rate]
new_avg_duration = new_result[:summary][:avg_duration]

puts "New implementation: #{new_success_rate}% success, #{(new_avg_duration * 1000).round(2)}ms avg"

# Performance regression check
if new_success_rate < baseline_success_rate - 1.0  # Allow 1% degradation
  puts "❌ Performance regression detected: success rate dropped"
  exit 1
elsif new_avg_duration > baseline_avg_duration * 1.2  # Allow 20% slowdown
  puts "❌ Performance regression detected: operations too slow"
  exit 1
else
  puts "✅ Performance regression test passed"
end
```

### Example 4: Custom Test Suite for Your Application

```ruby
# custom_app_test_suite.rb
require_relative 'configurable_stress_test'

class MyAppStressTest < ConfigurableStressTest
  # Define application-specific test scenarios
  def self.generate_app_specific_matrix
    # Based on your application's typical load patterns
    [
      # Morning rush hour simulation
      StressTestConfig.merge_and_validate(
        StressTestConfig.default,
        {
          thread_count: 100,    # High user concurrency
          pool_size: 25,        # Your production pool size
          operations_per_thread: 50,
          operation_mix: :read_heavy,  # Mostly reads in morning
          scenario: :rapid_fire
        }
      ),

      # End-of-day batch processing
      StressTestConfig.merge_and_validate(
        StressTestConfig.default,
        {
          thread_count: 20,     # Fewer concurrent users
          pool_size: 25,
          operations_per_thread: 500,  # Long-running operations
          operation_mix: :transaction_heavy,
          scenario: :long_transactions
        }
      ),

      # System maintenance window
      StressTestConfig.merge_and_validate(
        StressTestConfig.default,
        {
          thread_count: 5,      # Minimal activity
          pool_size: 10,        # Reduced pool during maintenance
          operations_per_thread: 100,
          operation_mix: :balanced,
          scenario: :mixed_workload
        }
      )
    ]
  end

  def self.run_app_scenarios
    puts "Running application-specific stress scenarios..."
    test_runner = new
    configs = generate_app_specific_matrix

    results = test_runner.run_test_matrix(configs)
    test_runner.display_matrix_summary(results, :app_scenarios)

    results
  end
end

# Usage
MyAppStressTest.run_app_scenarios
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
# .github/workflows/stress_test.yml
name: Connection Pool Stress Tests

on:
  pull_request:
    paths: ['lib/familia/**', 'try/prototypes/**']
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  stress_test:
    runs-on: ubuntu-latest

    services:
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true

      - name: Run CI stress tests
        run: |
          cd try/prototypes
          ruby configurable_stress_test.rb --ci
        env:
          REDIS_URL: redis://localhost:6379

      - name: Run custom scenarios
        if: github.event_name == 'schedule'
        run: |
          cd try/prototypes
          ruby run_stress_tests.rb --config heavy
        env:
          STRESS_THREADS: "20,50,100"
          STRESS_POOLS: "10,25"
          REDIS_URL: redis://localhost:6379

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: stress-test-results
          path: try/prototypes/stress_test_results_*/
```

### Jenkins Pipeline Example

```groovy
// Jenkinsfile
pipeline {
    agent any

    environment {
        REDIS_URL = 'redis://localhost:6379'
    }

    stages {
        stage('Setup') {
            steps {
                sh 'docker run -d -p 6379:6379 redis:7'
                sh 'bundle install'
            }
        }

        stage('Quick Validation') {
            steps {
                dir('try/prototypes') {
                    sh 'ruby configurable_stress_test.rb --development'
                }
            }
        }

        stage('Full Stress Test') {
            when {
                branch 'main'
            }
            steps {
                dir('try/prototypes') {
                    sh '''
                        export STRESS_THREADS=20,50,100
                        export STRESS_POOLS=10,20,50
                        ruby run_stress_tests.rb --runtime-config --verbose
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'try/prototypes/stress_test_results_*/**'
                }
            }
        }
    }
}
```

## Performance Analysis Workflows

### Workflow 1: Capacity Planning

```bash
#!/bin/bash
# capacity_planning.sh

echo "=== Connection Pool Capacity Planning ==="

# 1. Find baseline performance
echo "Step 1: Establishing baseline..."
ruby configurable_stress_test.rb --scope pool_sizing --quiet

# 2. Test thread scaling
echo "Step 2: Testing thread scalability..."
ruby configurable_stress_test.rb --scope thread_scaling --quiet

# 3. Test under different operation mixes
echo "Step 3: Testing operation mix impact..."
ruby configurable_stress_test.rb --scope operation_mixes --quiet

# 4. Generate comprehensive report
echo "Step 4: Generating analysis report..."
ruby visualize_stress_results.rb *.csv > capacity_analysis_report.md

echo "✅ Capacity planning analysis complete - see capacity_analysis_report.md"
```

### Workflow 2: Performance Monitoring

```ruby
# performance_monitor.rb
require_relative 'configurable_stress_test'

class PerformanceMonitor
  def self.run_health_check
    puts "Running connection pool health check..."

    # Standard health check configuration
    config = StressTestConfig.merge_and_validate(
      StressTestConfig.default,
      {
        thread_count: 20,
        pool_size: 10,
        operations_per_thread: 50,
        scenario: :mixed_workload
      }
    )

    test = ConfigurableStressTest.new
    result = test.run_single_config(config)
    summary = result[:summary]

    # Health check thresholds
    success_rate_threshold = 98.0
    avg_duration_threshold = 0.1  # 100ms

    health_status = "healthy"
    issues = []

    if summary[:success_rate] < success_rate_threshold
      health_status = "degraded"
      issues << "Low success rate: #{summary[:success_rate]}%"
    end

    if summary[:avg_duration] > avg_duration_threshold
      health_status = "degraded"
      issues << "High latency: #{(summary[:avg_duration] * 1000).round(2)}ms"
    end

    if summary[:failed_operations] > 0
      health_status = "degraded"
      issues << "#{summary[:failed_operations]} failed operations"
    end

    # Output structured result
    puts "Health Status: #{health_status.upcase}"
    puts "Success Rate: #{summary[:success_rate]}%"
    puts "Average Duration: #{(summary[:avg_duration] * 1000).round(2)}ms"
    puts "Failed Operations: #{summary[:failed_operations]}"

    if issues.any?
      puts "\nIssues Detected:"
      issues.each { |issue| puts "  - #{issue}" }
      exit 1
    else
      puts "\n✅ Connection pool is healthy"
      exit 0
    end
  end
end

# Usage
PerformanceMonitor.run_health_check
```

### Workflow 3: Load Testing Integration

```ruby
# load_test_integration.rb
require_relative 'configurable_stress_test'

# Simulate real application load patterns
class LoadTestIntegration
  def self.simulate_production_load
    puts "Simulating production load patterns..."

    # Define load patterns based on time of day
    patterns = {
      low_traffic: {
        thread_count: 10,
        operations_per_thread: 20,
        operation_mix: :balanced
      },

      medium_traffic: {
        thread_count: 50,
        operations_per_thread: 100,
        operation_mix: :read_heavy
      },

      high_traffic: {
        thread_count: 100,
        operations_per_thread: 200,
        operation_mix: :transaction_heavy
      },

      peak_traffic: {
        thread_count: 200,
        operations_per_thread: 100,
        operation_mix: :balanced
      }
    }

    results = {}
    test_runner = ConfigurableStressTest.new

    patterns.each do |pattern_name, overrides|
      puts "\nTesting #{pattern_name} pattern..."

      config = StressTestConfig.merge_and_validate(
        StressTestConfig.default,
        overrides.merge(
          pool_size: 25,  # Your production pool size
          scenario: :mixed_workload
        )
      )

      result = test_runner.run_single_config(config)
      results[pattern_name] = result

      puts "  #{pattern_name}: #{result[:summary][:success_rate]}% success"
    end

    # Analysis
    puts "\n=== Production Load Simulation Results ==="
    results.each do |pattern, result|
      summary = result[:summary]
      puts "#{pattern.to_s.ljust(15)}: #{summary[:success_rate]}% success, " \
           "#{(summary[:avg_duration] * 1000).round(2)}ms avg, " \
           "#{summary[:failed_operations]} failures"
    end

    # Find bottleneck
    worst_pattern = results.min_by { |_, result| result[:summary][:success_rate] }
    puts "\nBottleneck pattern: #{worst_pattern[0]}"

    results
  end
end

LoadTestIntegration.simulate_production_load
```

## Summary

The enhanced StressTestConfig system provides:

1. **Smart Configurations** - Predefined configs for different testing scenarios
2. **Systematic Testing** - Methodical approaches to test specific aspects
3. **Environment Integration** - Dynamic configuration from environment variables
4. **Validation** - Built-in configuration validation with warnings
5. **CI/CD Ready** - Easy integration with automated pipelines
6. **Analysis Tools** - Structured approaches to performance analysis

**Key Benefits**:
- Reduced setup time for stress testing
- Consistent and repeatable test configurations
- Built-in validation prevents configuration errors
- Easy integration with existing workflows
- Systematic approach to finding performance bottlenecks

This system transforms ad-hoc stress testing into a systematic, repeatable process that provides reliable insights into your connection pool's behavior under various conditions.
