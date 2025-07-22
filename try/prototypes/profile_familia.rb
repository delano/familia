#!/usr/bin/env ruby
# try/prototypes/profile_familia.rb
#
# Simple CLI for Familia Performance Profiling
#
# Usage:
#   ruby profile_familia.rb --quick          # Fast gut-check (default)
#   ruby profile_familia.rb --detailed       # Detailed profiling with ruby-prof
#   ruby profile_familia.rb --compare        # Compare against baselines only
#   ruby profile_familia.rb --update         # Update performance baselines
#   ruby profile_familia.rb --help           # Show help

require 'optparse'
require_relative 'lib/performance_profiler'
require_relative '../helpers/test_helpers'

class FamiliaProfileCLI
  def initialize(args)
    @options = parse_options(args)
    setup_environment
  end

  def run
    profiler = PerformanceProfiler.new(
      verbose: @options[:verbose],
      quiet: @options[:quiet]
    )

    case @options[:mode]
    when :quick
      run_quick_check(profiler)
    when :detailed
      run_detailed_profile(profiler)
    when :compare
      run_comparison_only(profiler)
    when :update
      run_baseline_update(profiler)
    else
      puts "Unknown mode: #{@options[:mode]}"
      exit 1
    end
  end

  private

  def parse_options(args)
    options = {
      mode: :quick,
      scenario: :mixed_workload,
      verbose: false,
      quiet: false
    }

    OptionParser.new do |opts|
      opts.banner = "Usage: profile_familia.rb [options]"
      opts.separator ""
      opts.separator "Modes:"

      opts.on("--quick", "Quick performance gut-check (default)") do
        options[:mode] = :quick
      end

      opts.on("--detailed", "Detailed profiling with ruby-prof analysis") do
        options[:mode] = :detailed
      end

      opts.on("--compare", "Compare against baselines only (no new tests)") do
        options[:mode] = :compare
      end

      opts.on("--update", "Update performance baselines") do
        options[:mode] = :update
      end

      opts.separator ""
      opts.separator "Options:"

      opts.on("-s", "--scenario SCENARIO", String, "Scenario for detailed profiling") do |s|
        options[:scenario] = s.to_sym
      end

      opts.on("-v", "--verbose", "Show detailed output") do
        options[:verbose] = true
      end

      opts.on("-q", "--quiet", "Suppress most output") do
        options[:quiet] = true
      end

      opts.on("-h", "--help", "Show this help") do
        puts opts
        puts ""
        puts "Examples:"
        puts "  profile_familia.rb                    # Quick gut-check"
        puts "  profile_familia.rb --detailed         # Full profiling"
        puts "  profile_familia.rb --detailed -s pool_siege_stress"
        puts "  profile_familia.rb --compare          # Just compare to baselines"
        puts "  profile_familia.rb --update           # Update baselines after improvements"
        puts ""
        puts "Scenarios for --detailed:"
        puts "  mixed_workload        - Balanced read/write/transaction mix (default)"
        puts "  pool_siege_stress     - High-load stress test"
        puts "  atomic_operations     - Focus on atomic save performance"
        puts "  connection_contention - Test connection pool under pressure"
        puts ""
        exit
      end
    end.parse!(args)

    options
  end

  def setup_environment
    # Initialize Familia environment
    Familia.debug = false

    # Clear Redis to ensure clean test environment
    if defined?(BankAccount)
      BankAccount.redis.flushdb
    end
  rescue => e
    puts "Warning: Could not initialize clean test environment: #{e.message}" unless @options[:quiet]
  end

  def run_quick_check(profiler)
    puts "🏃 Running quick performance check..." unless @options[:quiet]

    results = profiler.quick_check
    comparison = profiler.compare_baselines

    # Show summary
    unless @options[:quiet]
      puts ""
      puts "⏱️  Quick Check Summary:"
      results.each do |test, time|
        puts "   #{test}: #{time}s"
      end
    end

    # Exit with appropriate code for CI/automation
    critical_issues = comparison.values.count { |v| v[:status] == :critical }
    exit(critical_issues > 0 ? 1 : 0)
  end

  def run_detailed_profile(profiler)
    puts "🔍 Running detailed performance profile..." unless @options[:quiet]

    # Run detailed profiling
    result = profiler.detailed_profile(scenario: @options[:scenario])

    unless @options[:quiet]
      puts ""
      puts "📊 Detailed Profile Complete:"
      puts "   Scenario: #{@options[:scenario]}"
      puts "   Profile: #{result[:profile_file]}"
      puts "   Report: #{result[:report_file]}"
      puts ""
      puts "💡 To analyze the detailed results:"
      puts "   cat #{result[:report_file]}"
    end

    # Also run quick comparison
    profiler.quick_check
    profiler.compare_baselines
  end

  def run_comparison_only(profiler)
    puts "📊 Comparing against performance baselines..." unless @options[:quiet]

    # Load previous results or run fresh
    if profiler.results[:quick_check]&.any?
      comparison = profiler.compare_baselines
    else
      puts "No previous results found, running quick check first..." unless @options[:quiet]
      profiler.quick_check
      comparison = profiler.compare_baselines
    end

    unless @options[:quiet]
      puts ""
      puts "📈 Baseline Comparison Complete"

      good_count = comparison.values.count { |v| v[:status] == :good }
      total_count = comparison.size

      puts "   #{good_count}/#{total_count} tests within baseline thresholds"
    end

    # Exit with appropriate code
    critical_issues = comparison.values.count { |v| v[:status] == :critical }
    exit(critical_issues > 0 ? 1 : 0)
  end

  def run_baseline_update(profiler)
    puts "📈 Updating performance baselines..." unless @options[:quiet]

    # Run tests and update baselines
    results = profiler.quick_check
    updated_baselines = profiler.update_baselines(results)

    unless @options[:quiet]
      puts ""
      puts "✅ Baseline Update Complete"
      puts "   #{updated_baselines.size} tests have updated baselines"
      puts "   Use --compare to validate future runs against these baselines"
    end
  end
end

# Handle common case where someone just runs the script
if ARGV.empty?
  ARGV << '--quick'
end

# Run the CLI
if __FILE__ == $0
  begin
    cli = FamiliaProfileCLI.new(ARGV)
    cli.run
  rescue Interrupt
    puts "\n🛑 Profiling interrupted"
    exit 130
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(3) if ENV['DEBUG']
    exit 1
  end
end
