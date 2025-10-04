#!/usr/bin/env ruby
# try/prototypes/run_stress_tests.rb
#
# Main Test Runner for Connection Pool Stress Tests
#
# This script orchestrates comprehensive stress testing of the connection pool
# implementation across different scenarios, threading models, and configurations.
# It generates detailed reports and comparisons to identify bottlenecks and
# failure modes.

require 'optparse'
require 'fileutils'

require_relative 'lib/connection_pool_stress_test'
require_relative 'lib/connection_pool_threading_models'
require_relative 'lib/connection_pool_metrics'
require_relative 'lib/visualize_stress_results'

class StressTestRunner
  # Updated to use StressTestConfig systematically
  PREDEFINED_CONFIGS = {
    light: StressTestConfig.for_development,
    moderate: StressTestConfig.for_ci,
    heavy: StressTestConfig.for_production_validation,
    extreme: StressTestConfig.for_bottleneck_analysis,
    tuning: StressTestConfig.for_performance_tuning
  }

  def initialize(options = {})
    @options = {
      config_set: :moderate,
      output_dir: "stress_test_results_#{Familia.now.strftime('%Y%m%d_%H%M%S')}",
      threading_models: [:traditional, :thread_pool, :fiber],
      operation_mixes: [:balanced, :read_heavy, :write_heavy],
      generate_visualizations: true,
      verbose: false,
      use_runtime_config: false
    }.merge(options)

    # Use runtime config from environment if requested
    if @options[:use_runtime_config]
      runtime_overrides = StressTestConfig.runtime_config
      puts "Using runtime configuration overrides from environment" if @options[:verbose]
      @config_set = runtime_overrides
    else
      @config_set = PREDEFINED_CONFIGS[@options[:config_set]]
      raise ArgumentError, "Unknown config set: #{@options[:config_set]}" unless @config_set
    end

    @results_aggregator = ConnectionPoolMetrics::ResultAggregator.new

    setup_output_directory
  end

  def run_all_tests
    puts "=" * 80
    puts "CONNECTION POOL STRESS TEST SUITE"
    puts "=" * 80
    puts "Configuration: #{@options[:config_set]}"
    puts "Output directory: #{@options[:output_dir]}"
    puts "Threading models: #{@options[:threading_models].join(', ')}"
    puts "=" * 80

    total_tests = calculate_total_tests(@config_set)
    current_test = 0

    puts "Total tests to run: #{total_tests}"
    puts ""

    start_time = Familia.now

    @config_set[:scenarios].each do |scenario|
      puts "\n--- Testing Scenario: #{scenario} ---"

      @config_set[:thread_counts].each do |thread_count|
        @config_set[:operations_per_thread].each do |ops_per_thread|
          @config_set[:pool_sizes].each do |pool_size|
            @config_set[:pool_timeouts].each do |pool_timeout|
              @options[:operation_mixes].each do |operation_mix|
                @options[:threading_models].each do |threading_model|
                  current_test += 1

                  test_config = StressTestConfig.merge_and_validate(
                    StressTestConfig.default,
                    {
                      thread_count: thread_count,
                      operations_per_thread: ops_per_thread,
                      pool_size: pool_size,
                      pool_timeout: pool_timeout,
                      operation_mix: operation_mix,
                      scenario: scenario,
                      threading_model: threading_model
                    }
                  )

                  puts sprintf("[%d/%d] Running test: %s",
                              current_test, total_tests, format_test_config(test_config))

                  run_single_test(test_config)
                end
              end
            end
          end
        end
      end
    end

    duration = Familia.now - start_time
    puts "\n" + "=" * 80
    puts "ALL TESTS COMPLETED"
    puts "Total duration: #{format_duration(duration)}"
    puts "Results saved to: #{@options[:output_dir]}"

    generate_final_reports

    puts "=" * 80
  end

  def run_single_test(config)
    # Clean database
    BankAccount.dbclient.flushdb

    begin
      if config[:threading_model] == :traditional
        # Use original stress test for traditional threading
        test = ConnectionPoolStressTest.new(config)
        test.run
        metrics_summary = test.metrics.summary
        model_info = { name: 'traditional', details: {} }
      else
        # Use enhanced test for other threading models
        test = EnhancedConnectionPoolStressTest.new(config)
        model_info = test.run_with_model(config[:threading_model])
        metrics_summary = test.metrics.summary
      end

      # Save detailed results
      save_test_results(config, test.metrics, model_info)

      # Add to aggregator
      @results_aggregator.add_result(config, metrics_summary, model_info)

      # Print summary if verbose
      if @options[:verbose]
        puts "  Success rate: #{metrics_summary[:success_rate]}%"
        puts "  Avg duration: #{(metrics_summary[:avg_duration] * 1000).round(2)}ms"
        puts "  Errors: #{metrics_summary[:failed_operations]}"
      end

      return true

    rescue => e
      puts "  ERROR: #{e.message}"
      puts "  #{e.backtrace.first}" if @options[:verbose]

      # Record failed test
      error_info = {
        error: e.class.name,
        message: e.message,
        backtrace: e.backtrace.first(5)
      }

      @results_aggregator.add_result(
        config,
        { success_rate: 0, failed_operations: 1, total_operations: 0 },
        { name: config[:threading_model], error: error_info }
      )

      return false
    end
  end

  private

  def setup_output_directory
    FileUtils.mkdir_p(@options[:output_dir])
    FileUtils.mkdir_p(File.join(@options[:output_dir], 'individual_tests'))

    # Create README
    readme_content = generate_readme
    File.write(File.join(@options[:output_dir], 'README.md'), readme_content)
  end

  def calculate_total_tests(config_set)
    config_set[:scenarios].size *
    config_set[:thread_counts].size *
    config_set[:operations_per_thread].size *
    config_set[:pool_sizes].size *
    config_set[:pool_timeouts].size *
    @options[:operation_mixes].size *
    @options[:threading_models].size
  end

  def format_test_config(config)
    "#{config[:threading_model]}/#{config[:scenario]}/T#{config[:thread_count]}/O#{config[:operations_per_thread]}/P#{config[:pool_size]}/#{config[:operation_mix]}"
  end

  def format_duration(seconds)
    if seconds < 60
      "#{seconds.round(2)}s"
    elsif seconds < 3600
      "#{(seconds / 60).round(2)}m"
    else
      "#{(seconds / 3600).round(2)}h"
    end
  end

  def save_test_results(config, metrics, model_info)
    timestamp = Familia.now.strftime('%Y%m%d_%H%M%S_%L')
    test_id = "#{config[:threading_model]}_#{config[:scenario]}_#{timestamp}"

    # Export detailed CSV files
    if metrics.respond_to?(:export_detailed_csv)
      csv_prefix = File.join(@options[:output_dir], 'individual_tests', test_id)
      metrics.export_detailed_csv(csv_prefix)
    end

    # Save test configuration and results
    test_data = {
      timestamp: Familia.now,
      config: config,
      model_info: model_info,
      summary: metrics.respond_to?(:detailed_summary) ? metrics.detailed_summary : metrics.summary
    }

    File.write(
      File.join(@options[:output_dir], 'individual_tests', "#{test_id}_config.json"),
      JSON.pretty_generate(test_data)
    )
  end

  def generate_final_reports
    puts "\nGenerating final reports..."

    # Export aggregated comparison
    comparison_file = File.join(@options[:output_dir], 'comparison_results.csv')
    @results_aggregator.export_comparison_csv(comparison_file)

    # Generate comparison report
    comparison_report = @results_aggregator.generate_comparison_report
    File.write(File.join(@options[:output_dir], 'comparison_report.md'), comparison_report)

    # Generate visualizations if requested
    if @options[:generate_visualizations]
      generate_visualizations(comparison_file)
    end

    # Create executive summary
    executive_summary = generate_executive_summary
    File.write(File.join(@options[:output_dir], 'executive_summary.md'), executive_summary)

    puts "Reports generated:"
    puts "  - comparison_results.csv"
    puts "  - comparison_report.md"
    puts "  - executive_summary.md"
    puts "  - visualization_report.md" if @options[:generate_visualizations]
  end

  def generate_visualizations(comparison_file)
    visualizer = StressTestVisualizer.new([comparison_file])
    report = visualizer.generate_report

    File.write(File.join(@options[:output_dir], 'visualization_report.md'), report)
  end

  def generate_readme
    <<~README
    # Connection Pool Stress Test Results

    Generated: #{Familia.now}
    Configuration: #{@options[:config_set]}

    ## Directory Structure

    - `comparison_results.csv` - Aggregated comparison data
    - `comparison_report.md` - Analysis of all test configurations
    - `executive_summary.md` - High-level summary and recommendations
    - `visualization_report.md` - Charts and graphs (if generated)
    - `individual_tests/` - Detailed results for each test run

    ## Test Configuration

    - **Threading models tested**: #{@options[:threading_models].join(', ')}
    - **Operation mixes tested**: #{@options[:operation_mixes].join(', ')}
    - **Scenarios covered**: #{PREDEFINED_CONFIGS[@options[:config_set]][:scenarios].join(', ')}

    ## How to Analyze Results

    1. Start with `executive_summary.md` for key findings
    2. Review `comparison_report.md` for detailed analysis
    3. Check `visualization_report.md` for charts
    4. Examine individual test files in `individual_tests/` for deep dives

    ## Reproducing Tests

    To reproduce these tests, run:

    ```bash
    ruby run_stress_tests.rb --config #{@options[:config_set]} --output #{@options[:output_dir]}
    ```
    README
  end

  def generate_executive_summary
    summary = <<~SUMMARY
    # Executive Summary - Connection Pool Stress Testing

    **Generated**: #{Familia.now}
    **Test Configuration**: #{@options[:config_set]}

    ## Key Findings

    *[This would be populated with actual analysis results in a real implementation]*

    ### Performance Highlights

    - **Best performing threading model**: *TBD based on results*
    - **Most reliable configuration**: *TBD based on results*
    - **Recommended pool size**: *TBD based on results*

    ### Identified Issues

    - **Connection starvation threshold**: *TBD*
    - **Error patterns**: *TBD*
    - **Performance bottlenecks**: *TBD*

    ## Recommendations

    1. **Production Configuration**:
       - Pool size: *TBD*
       - Timeout: *TBD*
       - Threading model: *TBD*

    2. **Monitoring**:
       - Watch for pool utilization > X%
       - Alert on connection wait times > X seconds
       - Monitor error rates by operation type

    3. **Future Testing**:
       - Test with production-like workloads
       - Validate under network latency
       - Test failover scenarios

    ## Files for Deep Dive

    - `comparison_results.csv` - Raw performance data
    - `visualization_report.md` - Performance charts
    - `individual_tests/` - Detailed test results
    SUMMARY
  end
end

# Command-line interface
if __FILE__ == $0
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: run_stress_tests.rb [options]"

    opts.on("-c", "--config CONFIG", "Test configuration: light, moderate, heavy, extreme, tuning") do |config|
      options[:config_set] = config.to_sym
    end

    opts.on("-o", "--output DIR", "Output directory") do |dir|
      options[:output_dir] = dir
    end

    opts.on("-m", "--models MODELS", "Threading models (comma-separated): traditional,fiber,thread_pool,hybrid,actor") do |models|
      options[:threading_models] = models.split(',').map(&:strip).map(&:to_sym)
    end

    opts.on("-x", "--mixes MIXES", "Operation mixes (comma-separated): balanced,read_heavy,write_heavy,transaction_heavy") do |mixes|
      options[:operation_mixes] = mixes.split(',').map(&:strip).map(&:to_sym)
    end

    opts.on("-v", "--verbose", "Verbose output") do
      options[:verbose] = true
    end

    opts.on("--no-visualizations", "Skip visualization generation") do
      options[:generate_visualizations] = false
    end

    opts.on("--runtime-config", "Use configuration from environment variables") do
      options[:use_runtime_config] = true
    end

    opts.on("--validate-config", "Validate configuration and show warnings") do
      options[:validate_only] = true
    end

    opts.on("--list-configs", "List available configurations") do
      puts "Available configurations:"
      StressTestRunner::PREDEFINED_CONFIGS.each do |name, config|
        puts "  #{name}: #{config[:scenarios].join(', ')}"
      end
      puts "\nEnvironment variables for runtime config:"
      puts "  STRESS_THREADS=5,10,20    - Thread counts to test"
      puts "  STRESS_OPS=50,100         - Operations per thread"
      puts "  STRESS_POOLS=5,10,20      - Pool sizes to test"
      puts "  STRESS_TIMEOUTS=5,10      - Pool timeouts (seconds)"
      puts "  STRESS_SCENARIOS=rapid_fire,mixed_workload - Scenarios to run"
      puts "  STRESS_MIXES=balanced,read_heavy          - Operation mixes"
      exit
    end

    opts.on("--list-scenarios", "List available test scenarios") do
      puts "Available test scenarios:"
      StressTestConfig::SCENARIOS.each do |scenario|
        puts "  #{scenario}"
      end
      exit
    end

    opts.on("-h", "--help", "Show this help") do
      puts opts
      puts "\nExamples:"
      puts "  # Quick development test"
      puts "  ruby run_stress_tests.rb --config light --verbose"
      puts ""
      puts "  # Use environment configuration"
      puts "  STRESS_THREADS=10,50 STRESS_POOLS=5,10 ruby run_stress_tests.rb --runtime-config"
      puts ""
      puts "  # Validate a configuration"
      puts "  ruby run_stress_tests.rb --config extreme --validate-config"
      exit
    end
  end.parse!

  # Validate configuration
  if options[:config_set] && !StressTestRunner::PREDEFINED_CONFIGS.key?(options[:config_set])
    puts "Error: Unknown configuration '#{options[:config_set]}'"
    puts "Available: #{StressTestRunner::PREDEFINED_CONFIGS.keys.join(', ')}"
    exit 1
  end

  # Initialize Familia
  require_relative '../helpers/test_helpers'
  Familia.debug = false

  # Handle validation-only mode
  if options[:validate_only]
    puts "Validating configuration: #{options[:config_set] || 'runtime'}"

    if options[:use_runtime_config]
      config = StressTestConfig.runtime_config
      puts "Runtime configuration from environment:"
      config.each do |key, value|
        puts "  #{key}: #{value.join(', ')}"
      end
    else
      config_set = options[:config_set] || :moderate
      config = StressTestRunner::PREDEFINED_CONFIGS[config_set]
      puts "Predefined configuration: #{config_set}"
      config.each do |key, value|
        puts "  #{key}: #{value.join(', ')}"
      end
    end

    # Sample validation
    sample_config = StressTestConfig.merge_and_validate(
      StressTestConfig.default,
      {
        thread_count: 20,
        pool_size: 10,
        operations_per_thread: 100,
        scenario: :mixed_workload
      }
    )

    puts "\nSample configuration validation passed ✅"
    exit
  end

  puts "Initializing stress test runner..."
  runner = StressTestRunner.new(options)

  puts "Starting stress test suite..."
  runner.run_all_tests

  puts "\nStress test suite completed successfully!"
end
