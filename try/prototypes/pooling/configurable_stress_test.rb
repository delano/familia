# try/pooling/configurable_stress_test.rb
#
# Configurable Stress Test - Systematic testing using StressTestConfig
#
# This class provides methodical approaches to testing specific aspects
# of the connection pool by using the centralized StressTestConfig.

require_relative 'lib/connection_pool_stress_test'
require_relative 'lib/connection_pool_threading_models'
require_relative 'lib/connection_pool_metrics'

class ConfigurableStressTest
  attr_reader :results_aggregator

  def initialize
    @results_aggregator = ConnectionPoolMetrics::ResultAggregator.new
  end

  class << self
    # Generate test matrices for specific testing goals
    def generate_test_matrix(scope = :all)
      case scope
      when :thread_scaling
        # Test how performance scales with thread count
        StressTestConfig::THREAD_COUNTS.map do |thread_count|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            {
              thread_count: thread_count,
              pool_size: [thread_count / 2, 5].max, # Keep pool smaller than threads
              operations_per_thread: 100,
              scenario: :pool_starvation
            }
          )
        end

      when :pool_sizing
        # Test optimal pool sizes for different workloads
        StressTestConfig::POOL_SIZES.map do |pool_size|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            {
              thread_count: pool_size * 2, # Create pressure
              pool_size: pool_size,
              operations_per_thread: 50,
              scenario: :mixed_workload
            }
          )
        end

      when :operation_mixes
        # Test all operation patterns
        StressTestConfig::OPERATION_MIXES.keys.map do |mix|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            {
              thread_count: 20,
              pool_size: 10,
              operations_per_thread: 100,
              operation_mix: mix,
              scenario: :mixed_workload
            }
          )
        end

      when :timeout_behavior
        # Test different timeout scenarios
        StressTestConfig::POOL_TIMEOUTS.map do |timeout|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            {
              thread_count: 50, # High contention
              pool_size: 5,     # Small pool
              pool_timeout: timeout,
              operations_per_thread: 20, # Quick to see timeout effects
              scenario: :pool_starvation
            }
          )
        end

      when :scenario_comparison
        # Test all scenarios with consistent parameters
        StressTestConfig::SCENARIOS.map do |scenario|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            {
              scenario: scenario,
              thread_count: 20,
              pool_size: 10,
              operations_per_thread: 50
            }
          )
        end

      when :threading_models
        # Test different threading models
        [:traditional, :thread_pool, :fiber, :hybrid].map do |model|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            {
              threading_model: model,
              thread_count: 20,
              pool_size: 10,
              operations_per_thread: 100,
              scenario: :mixed_workload
            }
          )
        end

      when :high_contention
        # Test extreme contention scenarios
        [
          { thread_count: 100, pool_size: 5, scenario: :pool_starvation },
          { thread_count: 200, pool_size: 10, scenario: :rapid_fire },
          { thread_count: 50, pool_size: 5, scenario: :long_transactions }
        ].map do |config|
          StressTestConfig.merge_and_validate(
            StressTestConfig.default,
            config.merge(operations_per_thread: 50)
          )
        end

      when :comprehensive
        # Comprehensive test combining multiple dimensions
        configs = []
        StressTestConfig::SCENARIOS.each do |scenario|
          [10, 50].each do |threads|
            [5, 20].each do |pool_size|
              [:balanced, :transaction_heavy].each do |mix|
                configs << StressTestConfig.merge_and_validate(
                  StressTestConfig.default,
                  {
                    scenario: scenario,
                    thread_count: threads,
                    pool_size: pool_size,
                    operation_mix: mix,
                    operations_per_thread: 50
                  }
                )
              end
            end
          end
        end
        configs

      else
        raise ArgumentError, "Unknown test matrix scope: #{scope}. Valid: #{valid_scopes.join(', ')}"
      end
    end

    def valid_scopes
      [:thread_scaling, :pool_sizing, :operation_mixes, :timeout_behavior,
       :scenario_comparison, :threading_models, :high_contention, :comprehensive]
    end

    # Run targeted tests for a specific scope
    def run_targeted_tests(scope, options = {})
      puts "\n" + "=" * 80
      puts "RUNNING TARGETED TESTS: #{scope.to_s.upcase}"
      puts "=" * 80

      test_runner = new
      configs = generate_test_matrix(scope)

      puts "Generated #{configs.size} test configurations"

      results = test_runner.run_test_matrix(configs, options)

      puts "\n" + "=" * 80
      puts "TARGETED TEST RESULTS SUMMARY"
      puts "=" * 80
      test_runner.display_matrix_summary(results, scope)

      results
    end

    # Quick development tests using StressTestConfig
    def run_development_tests
      config_set = StressTestConfig.for_development
      run_config_set(config_set, "DEVELOPMENT")
    end

    # CI-appropriate tests
    def run_ci_tests
      config_set = StressTestConfig.for_ci
      run_config_set(config_set, "CI/CD")
    end

    # Production validation tests
    def run_production_validation_tests
      config_set = StressTestConfig.for_production_validation
      run_config_set(config_set, "PRODUCTION VALIDATION")
    end

    def run_config_set(config_set, name)
      puts "\n" + "=" * 80
      puts "#{name} TEST SUITE"
      puts "=" * 80

      test_runner = new
      total_configs = config_set.values.map(&:size).reduce(:*)
      puts "Total test configurations: #{total_configs}"

      # Generate all combinations
      configs = []
      config_set[:scenarios].each do |scenario|
        config_set[:thread_counts].each do |threads|
          config_set[:pool_sizes].each do |pool_size|
            config_set[:pool_timeouts].each do |timeout|
              config_set[:operation_mixes].each do |mix|
                configs << StressTestConfig.merge_and_validate(
                  StressTestConfig.default,
                  {
                    scenario: scenario,
                    thread_count: threads,
                    pool_size: pool_size,
                    pool_timeout: timeout,
                    operation_mix: mix,
                    operations_per_thread: config_set[:operations_per_thread].first
                  }
                )
              end
            end
          end
        end
      end

      results = test_runner.run_test_matrix(configs, { verbose: false })
      test_runner.display_matrix_summary(results, name.downcase.to_sym)

      results
    end
  end

  # Instance methods for running test matrices
  def run_test_matrix(configs, options = {})
    results = []
    verbose = options.fetch(:verbose, true)

    configs.each_with_index do |config, index|
      puts "\n[#{index + 1}/#{configs.size}] #{format_config_summary(config)}" if verbose

      begin
        # Clean database before each test
        BankAccount.dbclient.flushdb

        # Run the test
        result = run_single_config(config)
        results << { config: config, result: result, success: true }

        # Add to aggregator
        model_info = { name: config[:threading_model] || 'traditional' }
        @results_aggregator.add_result(config, result[:summary], model_info)

        # Quick result summary
        if verbose
          puts "  ✅ Success: #{result[:summary][:success_rate]}%, " \
               "Duration: #{(result[:summary][:avg_duration] * 1000).round(2)}ms"
        else
          print "."
        end

      rescue => e
        puts "  ❌ Error: #{e.message}" if verbose
        results << { config: config, error: e, success: false }

        # Record failed test
        error_summary = { success_rate: 0, failed_operations: 1, total_operations: 0 }
        @results_aggregator.add_result(config, error_summary, { error: e.message })
      end
    end

    puts "" unless verbose # newline after dots
    results
  end

  def run_single_config(config)
    if config[:threading_model] && config[:threading_model] != :traditional
      # Use enhanced test for non-traditional threading
      test = EnhancedConnectionPoolStressTest.new(config)
      model_info = test.run_with_model(config[:threading_model])
      { summary: test.metrics.summary, model_info: model_info }
    else
      # Use standard test
      test = ConnectionPoolStressTest.new(config)
      test.run
      { summary: test.metrics.summary, model_info: { name: 'traditional' } }
    end
  end

  def display_matrix_summary(results, scope)
    successful = results.count { |r| r[:success] }
    failed = results.count { |r| !r[:success] }

    puts "Results: #{successful}/#{results.size} tests passed (#{failed} failed)"

    if successful > 0
      # Find best and worst performers
      successful_results = results.select { |r| r[:success] }

      best = successful_results.max_by { |r| r[:result][:summary][:success_rate] }
      worst = successful_results.min_by { |r| r[:result][:summary][:success_rate] }

      puts "\nBest performer:"
      puts "  Config: #{format_config_summary(best[:config])}"
      puts "  Results: #{best[:result][:summary][:success_rate]}% success, " \
           "#{(best[:result][:summary][:avg_duration] * 1000).round(2)}ms avg"

      if best != worst
        puts "\nWorst performer:"
        puts "  Config: #{format_config_summary(worst[:config])}"
        puts "  Results: #{worst[:result][:summary][:success_rate]}% success, " \
             "#{(worst[:result][:summary][:avg_duration] * 1000).round(2)}ms avg"
      end

      # Specific insights based on scope
      display_scope_specific_insights(successful_results, scope)
    end

    if failed > 0
      puts "\nFailed configurations:"
      results.select { |r| !r[:success] }.each do |failure|
        puts "  #{format_config_summary(failure[:config])} - #{failure[:error].message}"
      end
    end
  end

  private

  def format_config_summary(config)
    parts = []
    parts << "#{config[:scenario]}" if config[:scenario]
    parts << "T#{config[:thread_count]}" if config[:thread_count]
    parts << "P#{config[:pool_size]}" if config[:pool_size]
    parts << "#{config[:operation_mix]}" if config[:operation_mix]
    parts << "#{config[:threading_model]}" if config[:threading_model] && config[:threading_model] != :traditional
    parts.join("/")
  end

  def display_scope_specific_insights(results, scope)
    case scope
    when :thread_scaling
      puts "\nThread Scaling Insights:"
      thread_performance = results.group_by { |r| r[:config][:thread_count] }
      thread_performance.each do |threads, group|
        avg_success = group.map { |r| r[:result][:summary][:success_rate] }.sum / group.size
        puts "  #{threads} threads: #{avg_success.round(1)}% avg success rate"
      end

    when :pool_sizing
      puts "\nPool Sizing Insights:"
      pool_performance = results.group_by { |r| r[:config][:pool_size] }
      pool_performance.each do |pool_size, group|
        avg_duration = group.map { |r| r[:result][:summary][:avg_duration] }.sum / group.size
        puts "  Pool size #{pool_size}: #{(avg_duration * 1000).round(2)}ms avg duration"
      end

    when :operation_mixes
      puts "\nOperation Mix Insights:"
      mix_performance = results.group_by { |r| r[:config][:operation_mix] }
      mix_performance.each do |mix, group|
        avg_success = group.map { |r| r[:result][:summary][:success_rate] }.sum / group.size
        puts "  #{mix}: #{avg_success.round(1)}% avg success rate"
      end
    end
  end
end

# Example usage and CLI runner
if __FILE__ == $0
  require 'optparse'

  options = { scope: :thread_scaling, verbose: true }

  OptionParser.new do |opts|
    opts.banner = "Usage: configurable_stress_test.rb [options]"

    opts.on("-s", "--scope SCOPE", "Test scope: #{ConfigurableStressTest.valid_scopes.join(', ')}") do |scope|
      options[:scope] = scope.to_sym
    end

    opts.on("-q", "--quiet", "Quiet output") do
      options[:verbose] = false
    end

    opts.on("--development", "Run development test suite") do
      options[:preset] = :development
    end

    opts.on("--ci", "Run CI test suite") do
      options[:preset] = :ci
    end

    opts.on("--production", "Run production validation suite") do
      options[:preset] = :production_validation
    end

    opts.on("--list-scopes", "List available test scopes") do
      puts "Available test scopes:"
      ConfigurableStressTest.valid_scopes.each do |scope|
        puts "  #{scope}"
      end
      exit
    end

    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!

  # Initialize Familia
  require_relative '../helpers/test_helpers'
  Familia.debug = false

  if options[:preset]
    case options[:preset]
    when :development
      ConfigurableStressTest.run_development_tests
    when :ci
      ConfigurableStressTest.run_ci_tests
    when :production_validation
      ConfigurableStressTest.run_production_validation_tests
    end
  else
    # Run targeted tests
    unless ConfigurableStressTest.valid_scopes.include?(options[:scope])
      puts "Error: Unknown scope '#{options[:scope]}'"
      puts "Valid scopes: #{ConfigurableStressTest.valid_scopes.join(', ')}"
      exit 1
    end

    ConfigurableStressTest.run_targeted_tests(options[:scope], options)
  end
end
