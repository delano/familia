# try/prototypes/lib/performance_profiler.rb
#
# Lightweight Performance Profiler for Familia
#
# A simple, scrappy profiling system for gut-check performance validation.
# Designed to be run occasionally to catch performance regressions.
#
# Usage:
#   profiler = PerformanceProfiler.new
#   profiler.quick_check          # Fast gut-check
#   profiler.detailed_profile     # Detailed analysis
#   profiler.compare_baselines    # Compare against known good values

require 'benchmark'
require 'json'
require 'ruby-prof'

class PerformanceProfiler
  attr_reader :results

  def initialize(options = {})
    @options = {
      verbose: false,
      output_dir: File.join(__dir__, '..', 'profile_results'),
      baseline_file: File.join(__dir__, 'performance_baselines.json')
    }.merge(options)

    @results = {}
    ensure_output_dir
  end

  # Quick performance gut-check - should complete in <5 seconds
  def quick_check
    puts "🏃 Familia Performance Quick Check" unless @options[:quiet]

    @results[:quick_check] = {}

    # Test 1: Basic operations
    time = benchmark_test("basic_operations") do
      run_basic_operations(count: 10)
    end
    @results[:quick_check][:basic_operations] = time

    # Test 2: Pool setup
    time = benchmark_test("pool_setup") do
      setup_connection_pool
    end
    @results[:quick_check][:pool_setup] = time

    # Test 3: Quick siege test (like --quick but without progress display)
    time = benchmark_test("pool_siege_quick") do
      run_siege_test(threads: 2, operations: 10, quiet: true)
    end
    @results[:quick_check][:pool_siege_quick] = time

    # Test 4: Thread safety check
    time = benchmark_test("thread_safety") do
      run_thread_safety_test
    end
    @results[:quick_check][:thread_safety] = time

    display_quick_results unless @options[:quiet]
    @results[:quick_check]
  end

  # Detailed profiling with ruby-prof for investigation
  def detailed_profile(scenario: :mixed_workload)
    puts "🔍 Detailed Performance Profile (#{scenario})" unless @options[:quiet]

    @results[:detailed] = {}

    # Set up profiling
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    profile_file = File.join(@options[:output_dir], "detailed_#{scenario}_#{timestamp}.dump")

    # Run with profiling
    result = RubyProf::Profile.new.tap do |profile|
      profile.start

      case scenario
      when :pool_siege_stress
        run_siege_test(threads: 10, operations: 50, quiet: true)
      when :atomic_operations
        run_atomic_operations_test
      when :connection_contention
        run_connection_contention_test
      else
        run_siege_test(threads: 2, operations: 20, quiet: true)
      end

      profile.stop
    end

    # Save profile for later analysis
    File.open(profile_file, 'wb') do |file|
      Marshal.dump(result.data, file)
    end

    # Generate text report
    report_file = profile_file.gsub('.dump', '_report.txt')
    File.open(report_file, 'w') do |file|
      printer = RubyProf::FlatPrinter.new(result)
      printer.print(file, min_percent: 1)
    end

    @results[:detailed] = {
      profile_file: profile_file,
      report_file: report_file,
      scenario: scenario
    }

    puts "📊 Profile saved to: #{profile_file}" unless @options[:quiet]
    puts "📋 Report saved to: #{report_file}" unless @options[:quiet]

    @results[:detailed]
  end

  # Compare results against known baselines
  def compare_baselines(baseline_data = nil)
    baseline_data ||= load_baselines
    return { error: "No baseline data available" } if baseline_data.empty?

    quick_results = @results[:quick_check] || quick_check
    comparison = {}

    quick_results.each do |test_name, actual_time|
      baseline = baseline_data[test_name.to_s]
      next unless baseline

      status = if actual_time <= baseline['good_threshold']
                 :good
               elsif actual_time <= baseline['warning_threshold']
                 :warning
               else
                 :critical
               end

      comparison[test_name] = {
        actual: actual_time,
        baseline_good: baseline['good_threshold'],
        baseline_warning: baseline['warning_threshold'],
        status: status,
        ratio: (actual_time / baseline['good_threshold']).round(2)
      }
    end

    @results[:comparison] = comparison
    display_comparison_results(comparison) unless @options[:quiet]
    comparison
  end

  # Update baselines when performance improves
  def update_baselines(test_results = nil)
    test_results ||= @results[:quick_check] || quick_check
    baselines = load_baselines

    test_results.each do |test_name, time|
      key = test_name.to_s
      current_baseline = baselines[key] || {}

      # Set good threshold as 1.5x the measured time, warning as 2.5x
      new_good = (time * 1.5).round(4)
      new_warning = (time * 2.5).round(4)

      # Only update if this is better than current baseline
      if current_baseline.empty? || new_good < current_baseline['good_threshold']
        baselines[key] = {
          'good_threshold' => new_good,
          'warning_threshold' => new_warning,
          'last_updated' => Time.now.iso8601,
          'sample_time' => time
        }
        puts "📈 Updated baseline for #{test_name}: #{time}s -> #{new_good}s" unless @options[:quiet]
      end
    end

    save_baselines(baselines)
    baselines
  end

  private

  def benchmark_test(name)
    print "  #{name}..." if @options[:verbose] && !@options[:quiet]

    time = Benchmark.realtime { yield }

    puts " #{time.round(4)}s" if @options[:verbose] && !@options[:quiet]
    time.round(4)
  end

  def run_basic_operations(count: 10)
    require_relative '../lib/atomic_saves_v3_connection_pool_helpers'

    count.times do |i|
      account = BankAccount.new
      account.balance = 1000
      account.holder_name = "Test#{i}"
      account.save
      account.refresh!
      account.balance = account.balance + 10
      account.save
    end
  end

  def setup_connection_pool
    require_relative '../lib/connection_pool_stress_test'

    Familia.class_eval do
      @@connection_pool = ConnectionPool.new(size: 5, timeout: 10) do
        Redis.new(url: Familia.uri.to_s)
      end
    end
  end

  def run_siege_test(threads: 2, operations: 10, quiet: true)
    require_relative '../lib/connection_pool_stress_test'

    test = ConnectionPoolStressTest.new({
      thread_count: threads,
      operations_per_thread: operations,
      pool_size: 2,
      pool_timeout: 10,
      operation_mix: :balanced,
      scenario: :mixed_workload
    })

    test.run
  end

  def run_thread_safety_test
    require_relative '../lib/atomic_saves_v3_connection_pool_helpers'

    threads = []
    account = BankAccount.new
    account.balance = 1000
    account.holder_name = "ThreadSafety"
    account.save

    5.times do
      threads << Thread.new do
        3.times do
          Familia.atomic do
            account.refresh!
            current = account.balance || 0
            account.balance = current + 1
            account.save
          end
        end
      end
    end

    threads.each(&:join)
  end

  def run_atomic_operations_test
    require_relative '../lib/atomic_saves_v3_connection_pool_helpers'

    account = BankAccount.new
    account.balance = 1000
    account.holder_name = "AtomicTest"
    account.save

    20.times do
      Familia.atomic do
        account.refresh!
        current = account.balance || 0
        account.balance = current + 1
        account.save
      end
    end
  end

  def run_connection_contention_test
    require_relative '../lib/connection_pool_stress_test'

    test = ConnectionPoolStressTest.new({
      thread_count: 10,
      operations_per_thread: 10,
      pool_size: 3,  # Force contention
      pool_timeout: 10,
      operation_mix: :balanced,
      scenario: :pool_starvation
    })

    test.run
  end

  def display_quick_results
    puts "\n📊 Results:"
    @results[:quick_check].each do |test, time|
      status_icon = time < 0.1 ? "✅" : time < 0.5 ? "⚠️" : "❌"
      puts "#{status_icon} #{test}: #{time}s"
    end
  end

  def display_comparison_results(comparison)
    puts "\n📊 Baseline Comparison:"
    overall_status = :good

    comparison.each do |test, data|
      icon = case data[:status]
             when :good then "✅"
             when :warning then "⚠️"
             when :critical then "❌"
             end

      overall_status = data[:status] if data[:status] != :good && overall_status == :good

      puts "#{icon} #{test}: #{data[:actual]}s (baseline: #{data[:baseline_good]}s, ratio: #{data[:ratio]}x)"
    end

    puts "\nOverall: #{overall_status == :good ? '🟢 HEALTHY' : overall_status == :warning ? '🟡 DEGRADED' : '🔴 CRITICAL'}"
  end

  def load_baselines
    return {} unless File.exist?(@options[:baseline_file])
    JSON.parse(File.read(@options[:baseline_file]))
  rescue JSON::ParserError
    {}
  end

  def save_baselines(baselines)
    File.write(@options[:baseline_file], JSON.pretty_generate(baselines))
  end

  def ensure_output_dir
    FileUtils.mkdir_p(@options[:output_dir]) unless Dir.exist?(@options[:output_dir])
  rescue
    # Fallback to current directory if we can't create the output dir
    @options[:output_dir] = Dir.pwd
  end
end
