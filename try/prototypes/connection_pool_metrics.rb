# try/prototypes/connection_pool_metrics.rb
#
# Enhanced Metrics Collection and Reporting for Connection Pool Stress Tests
#
# This module provides detailed metrics collection, analysis, and export
# capabilities for stress test results. Outputs include CSV, summary reports,
# and simple ASCII visualizations.

require 'csv'
require 'json'

module ConnectionPoolMetrics
  # Enhanced metrics collector with detailed tracking
  class DetailedMetricsCollector < MetricsCollector
    def initialize
      super
      @metrics[:connection_acquisitions] = []
      @metrics[:thread_states] = []
      @metrics[:pool_exhaustion_events] = []
      @mutex = Mutex.new
    end
    
    def record_connection_acquisition(thread_id, wait_time, acquired)
      @mutex.synchronize do
        @metrics[:connection_acquisitions] << {
          thread_id: thread_id,
          wait_time: wait_time,
          acquired: acquired,
          timestamp: Time.now.to_f
        }
      end
    end
    
    def record_thread_state(thread_id, state, context = {})
      @mutex.synchronize do
        @metrics[:thread_states] << {
          thread_id: thread_id,
          state: state, # :waiting, :running, :completed, :failed
          context: context,
          timestamp: Time.now.to_f
        }
      end
    end
    
    def record_pool_exhaustion(wait_time, thread_count_waiting)
      @mutex.synchronize do
        @metrics[:pool_exhaustion_events] << {
          wait_time: wait_time,
          threads_waiting: thread_count_waiting,
          timestamp: Time.now.to_f
        }
      end
    end
    
    def detailed_summary
      summary = super
      
      # Add connection acquisition stats
      acquisitions = @metrics[:connection_acquisitions]
      if acquisitions.any?
        wait_times = acquisitions.map { |a| a[:wait_time] }
        summary[:connection_stats] = {
          total_acquisitions: acquisitions.size,
          successful_acquisitions: acquisitions.count { |a| a[:acquired] },
          avg_wait_time: wait_times.sum.to_f / wait_times.size,
          max_wait_time: wait_times.max,
          min_wait_time: wait_times.min,
          p95_wait_time: percentile(wait_times, 0.95),
          p99_wait_time: percentile(wait_times, 0.99)
        }
      end
      
      # Add pool exhaustion stats
      if @metrics[:pool_exhaustion_events].any?
        summary[:pool_exhaustion] = {
          total_events: @metrics[:pool_exhaustion_events].size,
          max_threads_waiting: @metrics[:pool_exhaustion_events].map { |e| e[:threads_waiting] }.max
        }
      end
      
      # Add operation breakdown by type
      operations_by_type = @metrics[:operations].group_by { |op| op[:type] }
      summary[:operations_by_type] = {}
      
      operations_by_type.each do |type, ops|
        successful = ops.count { |op| op[:success] }
        durations = ops.map { |op| op[:duration] }
        
        summary[:operations_by_type][type] = {
          count: ops.size,
          success_rate: (successful.to_f / ops.size * 100).round(2),
          avg_duration: durations.sum.to_f / durations.size,
          p95_duration: percentile(durations, 0.95),
          p99_duration: percentile(durations, 0.99)
        }
      end
      
      summary
    end
    
    def export_detailed_csv(filename_prefix = "stress_test")
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      
      # Export operations
      CSV.open("#{filename_prefix}_operations_#{timestamp}.csv", "w") do |csv|
        csv << ['timestamp', 'type', 'duration', 'success', 'wait_time']
        @metrics[:operations].each do |op|
          csv << [op[:timestamp], op[:type], op[:duration], op[:success], op[:wait_time]]
        end
      end
      
      # Export errors
      if @metrics[:errors].any?
        CSV.open("#{filename_prefix}_errors_#{timestamp}.csv", "w") do |csv|
          csv << ['timestamp', 'error_type', 'message', 'context']
          @metrics[:errors].each do |err|
            csv << [err[:timestamp], err[:error], err[:message], err[:context].to_json]
          end
        end
      end
      
      # Export pool stats
      if @metrics[:pool_stats].any?
        CSV.open("#{filename_prefix}_pool_stats_#{timestamp}.csv", "w") do |csv|
          csv << ['timestamp', 'available', 'size', 'utilization']
          @metrics[:pool_stats].each do |stat|
            csv << [stat[:timestamp], stat[:available], stat[:size], stat[:utilization]]
          end
        end
      end
      
      # Export summary
      CSV.open("#{filename_prefix}_summary_#{timestamp}.csv", "w") do |csv|
        csv << ['metric', 'value']
        flatten_hash(detailed_summary).each do |key, value|
          csv << [key, value]
        end
      end
      
      puts "Exported CSV files with prefix: #{filename_prefix}_*_#{timestamp}.csv"
    end
    
    def generate_ascii_report
      summary = detailed_summary
      
      report = []
      report << "\n" + "=" * 80
      report << "CONNECTION POOL STRESS TEST REPORT"
      report << "=" * 80
      
      # Overall Summary
      report << "\nOVERALL SUMMARY:"
      report << "-" * 40
      report << sprintf("Total Operations: %d", summary[:total_operations])
      report << sprintf("Success Rate: %.2f%%", summary[:success_rate])
      report << sprintf("Average Duration: %.4f seconds", summary[:avg_duration])
      
      # Connection Statistics
      if summary[:connection_stats]
        report << "\nCONNECTION ACQUISITION STATISTICS:"
        report << "-" * 40
        stats = summary[:connection_stats]
        report << sprintf("Total Acquisitions: %d", stats[:total_acquisitions])
        report << sprintf("Successful: %d (%.2f%%)", 
                         stats[:successful_acquisitions],
                         stats[:successful_acquisitions].to_f / stats[:total_acquisitions] * 100)
        report << sprintf("Avg Wait Time: %.4f seconds", stats[:avg_wait_time])
        report << sprintf("Max Wait Time: %.4f seconds", stats[:max_wait_time])
        report << sprintf("P95 Wait Time: %.4f seconds", stats[:p95_wait_time])
        report << sprintf("P99 Wait Time: %.4f seconds", stats[:p99_wait_time])
      end
      
      # Operations by Type
      if summary[:operations_by_type] && summary[:operations_by_type].any?
        report << "\nOPERATIONS BY TYPE:"
        report << "-" * 40
        report << sprintf("%-15s %10s %10s %10s %10s", "Type", "Count", "Success%", "Avg(ms)", "P95(ms)")
        
        summary[:operations_by_type].each do |type, stats|
          report << sprintf("%-15s %10d %10.2f %10.2f %10.2f",
                           type,
                           stats[:count],
                           stats[:success_rate],
                           stats[:avg_duration] * 1000,
                           stats[:p95_duration] * 1000)
        end
      end
      
      # Pool Utilization Graph
      if @metrics[:pool_stats].any?
        report << "\nPOOL UTILIZATION OVER TIME:"
        report << "-" * 40
        report << generate_utilization_graph
      end
      
      # Error Summary
      if summary[:errors_by_type] && summary[:errors_by_type].any?
        report << "\nERROR SUMMARY:"
        report << "-" * 40
        summary[:errors_by_type].each do |error_type, count|
          report << sprintf("%-30s: %d", error_type, count)
        end
      end
      
      report << "\n" + "=" * 80
      
      report.join("\n")
    end
    
    private
    
    def percentile(values, percentile)
      return 0 if values.empty?
      sorted = values.sort
      index = (percentile * (sorted.length - 1)).round
      sorted[index]
    end
    
    def flatten_hash(hash, prefix = '')
      hash.each_with_object({}) do |(key, value), result|
        new_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        if value.is_a?(Hash)
          result.merge!(flatten_hash(value, new_key))
        else
          result[new_key] = value
        end
      end
    end
    
    def generate_utilization_graph
      return "No pool stats available" if @metrics[:pool_stats].empty?
      
      # Sample data points for ASCII graph
      samples = 50
      stats = @metrics[:pool_stats]
      sample_interval = [stats.size / samples, 1].max
      
      sampled_stats = []
      (0...stats.size).step(sample_interval) do |i|
        sampled_stats << stats[i]
      end
      
      # Create ASCII graph
      graph_height = 10
      graph = Array.new(graph_height + 1) { ' ' * samples }
      
      sampled_stats.each_with_index do |stat, i|
        height = (stat[:utilization] / 100.0 * graph_height).round
        (0..height).each do |h|
          graph[graph_height - h][i] = '*'
        end
      end
      
      # Add scale
      result = []
      result << "100% |" + graph[0]
      (1...graph_height).each do |i|
        percent = 100 - (i * 10)
        result << sprintf("%3d%% |", percent) + graph[i]
      end
      result << "  0% |" + graph[graph_height]
      result << "     +" + "-" * samples
      result << "      " + "Time →"
      
      result.join("\n")
    end
  end
  
  # Test result aggregator for multiple runs
  class ResultAggregator
    def initialize
      @results = []
    end
    
    def add_result(config, metrics_summary, model_info = {})
      @results << {
        timestamp: Time.now,
        config: config,
        summary: metrics_summary,
        model: model_info
      }
    end
    
    def export_comparison_csv(filename = "comparison_results.csv")
      CSV.open(filename, "w") do |csv|
        # Headers
        headers = ['timestamp', 'model', 'threads', 'ops_per_thread', 'pool_size', 
                   'pool_timeout', 'scenario', 'success_rate', 'avg_duration', 
                   'avg_wait_time', 'max_pool_util', 'errors']
        csv << headers
        
        # Data rows
        @results.each do |result|
          csv << [
            result[:timestamp].strftime("%Y-%m-%d %H:%M:%S"),
            result[:model][:name] || 'default',
            result[:config][:thread_count],
            result[:config][:operations_per_thread],
            result[:config][:pool_size],
            result[:config][:pool_timeout],
            result[:config][:scenario],
            result[:summary][:success_rate],
            result[:summary][:avg_duration],
            result[:summary][:avg_wait_time],
            result[:summary][:max_pool_utilization],
            result[:summary][:failed_operations]
          ]
        end
      end
      
      puts "Comparison results exported to: #{filename}"
    end
    
    def generate_comparison_report
      report = []
      report << "\nCOMPARISON REPORT"
      report << "=" * 80
      
      # Group by scenario
      by_scenario = @results.group_by { |r| r[:config][:scenario] }
      
      by_scenario.each do |scenario, results|
        report << "\nScenario: #{scenario}"
        report << "-" * 40
        
        # Find best and worst performers
        sorted = results.sort_by { |r| -r[:summary][:success_rate] }
        best = sorted.first
        worst = sorted.last
        
        report << sprintf("Best performer: %s (%.2f%% success rate)",
                         best[:model][:name] || 'default',
                         best[:summary][:success_rate])
        report << sprintf("Worst performer: %s (%.2f%% success rate)",
                         worst[:model][:name] || 'default',
                         worst[:summary][:success_rate])
      end
      
      report.join("\n")
    end
  end
end

# Example usage
if __FILE__ == $0
  # Create detailed metrics collector
  metrics = ConnectionPoolMetrics::DetailedMetricsCollector.new
  
  # Simulate some operations
  10.times do |i|
    metrics.record_operation(:read, rand(0.001..0.1), rand < 0.95, rand(0.0..0.01))
    metrics.record_connection_acquisition(i, rand(0.0..0.5), rand < 0.9)
  end
  
  5.times do |i|
    metrics.record_pool_stats(rand(0..10), 10)
  end
  
  # Generate reports
  puts metrics.generate_ascii_report
  metrics.export_detailed_csv("test_run")
  
  # Test aggregator
  aggregator = ConnectionPoolMetrics::ResultAggregator.new
  aggregator.add_result(
    { thread_count: 10, pool_size: 5, scenario: :test },
    metrics.detailed_summary,
    { name: 'test_model' }
  )
  
  aggregator.export_comparison_csv
end