#!/usr/bin/env ruby
# try/support/prototypes/pooling/lib/visualize_stress_results.rb
#
# frozen_string_literal: true

# try/prototypes/visualize_stress_results.rb
# Simple Visualization Tool for Connection Pool Stress Test Results
# This script reads CSV output from stress tests and generates:
# - ASCII charts for terminal display
# - Markdown-formatted reports
# - Comparison tables
# - Performance trend analysis

require 'csv'
require 'optparse'

class StressTestVisualizer
  def initialize(csv_files = [])
    @csv_files = csv_files
    @data = {}
    load_data
  end

  def load_data
    @csv_files.each do |file|
      next unless File.exist?(file)

      type = detect_csv_type(file)
      @data[type] ||= []

      CSV.foreach(file, headers: true) do |row|
        @data[type] << row.to_h
      end
    end
  end

  def detect_csv_type(filename)
    case filename
    when /operations/ then :operations
    when /errors/ then :errors
    when /pool_stats/ then :pool_stats
    when /summary/ then :summary
    when /comparison/ then :comparison
    else :unknown
    end
  end

  def generate_report
    report = []
    report << "# Connection Pool Stress Test Results"
    report << "\nGenerated: #{Familia.now}"
    report << "\n"

    # Summary section
    if @data[:summary]
      report << "## Summary"
      report << generate_summary_table
      report << "\n"
    end

    # Performance charts
    if @data[:operations]
      report << "## Performance Analysis"
      report << generate_performance_analysis
      report << "\n"
    end

    # Pool utilization
    if @data[:pool_stats]
      report << "## Pool Utilization"
      report << generate_pool_utilization_chart
      report << "\n"
    end

    # Error analysis
    if @data[:errors] && @data[:errors].any?
      report << "## Error Analysis"
      report << generate_error_analysis
      report << "\n"
    end

    # Comparison
    if @data[:comparison]
      report << "## Configuration Comparison"
      report << generate_comparison_table
      report << "\n"
    end

    report.join("\n")
  end

  def generate_summary_table
    return "No summary data available" unless @data[:summary]

    table = []
    table << "| Metric | Value |"
    table << "|--------|-------|"

    @data[:summary].each do |row|
      metric = row['metric'] || row[:metric]
      value = row['value'] || row[:value]

      # Format numeric values
      if value.to_s =~ /^\d+\.?\d*$/
        value = format_number(value.to_f)
      end

      table << "| #{metric} | #{value} |"
    end

    table.join("\n")
  end

  def generate_performance_analysis
    return "No operations data available" unless @data[:operations]

    analysis = []

    # Calculate percentiles
    durations = @data[:operations].map { |op| op['duration'].to_f }.sort

    analysis << "### Response Time Distribution"
    analysis << "```"
    analysis << generate_histogram(durations, 20)
    analysis << "```"

    # Operations over time
    analysis << "\n### Operations Timeline"
    analysis << "```"
    analysis << generate_timeline_chart(@data[:operations])
    analysis << "```"

    # Success rate by operation type
    by_type = @data[:operations].group_by { |op| op['type'] }

    analysis << "\n### Success Rate by Operation Type"
    analysis << "| Type | Total | Success | Rate |"
    analysis << "|------|-------|---------|------|"

    by_type.each do |type, ops|
      total = ops.size
      success = ops.count { |op| op['success'] == 'true' }
      rate = (success.to_f / total * 100).round(2)

      analysis << "| #{type} | #{total} | #{success} | #{rate}% |"
    end

    analysis.join("\n")
  end

  def generate_pool_utilization_chart
    return "No pool stats available" unless @data[:pool_stats]

    chart = []
    chart << "```"

    # Get utilization values
    utils = @data[:pool_stats].map { |stat| stat['utilization'].to_f }

    # Create time-series chart
    chart_height = 15
    chart_width = [utils.size, 80].min

    # Sample if too many data points
    if utils.size > chart_width
      sample_rate = utils.size / chart_width
      sampled_utils = []
      (0...chart_width).each do |i|
        sampled_utils << utils[i * sample_rate]
      end
      utils = sampled_utils
    end

    # Build chart
    (0..10).each do |i|
      level = 100 - (i * 10)
      line = sprintf("%3d%% |", level)

      utils.each do |util|
        if util >= level - 5 && util < level + 5
          line += "●"
        elsif util >= level
          line += "│"
        else
          line += " "
        end
      end

      chart << line
    end

    chart << "  0% |" + "─" * utils.size
    chart << "     " + " " * (utils.size / 2 - 2) + "Time"
    chart << "```"

    # Add statistics
    chart << "\n**Pool Utilization Statistics:**"
    chart << "- Average: #{(utils.sum / utils.size).round(2)}%"
    chart << "- Maximum: #{utils.max.round(2)}%"
    chart << "- Minimum: #{utils.min.round(2)}%"

    chart.join("\n")
  end

  def generate_error_analysis
    return "No errors recorded" unless @data[:errors] && @data[:errors].any?

    analysis = []

    # Group by error type
    by_type = @data[:errors].group_by { |err| err['error_type'] }

    analysis << "### Error Distribution"
    analysis << "| Error Type | Count | Percentage |"
    analysis << "|------------|-------|------------|"

    total_errors = @data[:errors].size

    by_type.each do |type, errors|
      count = errors.size
      percentage = (count.to_f / total_errors * 100).round(2)
      analysis << "| #{type} | #{count} | #{percentage}% |"
    end

    # Error timeline
    analysis << "\n### Error Timeline"
    analysis << "```"
    analysis << generate_error_timeline(@data[:errors])
    analysis << "```"

    analysis.join("\n")
  end

  def generate_comparison_table
    return "No comparison data available" unless @data[:comparison]

    table = []
    table << "### Test Configuration Comparison"
    table << ""

    # Create comparison table
    headers = @data[:comparison].first.keys
    table << "| " + headers.join(" | ") + " |"
    table << "|" + headers.map { "-" * 10 }.join("|") + "|"

    @data[:comparison].each do |row|
      values = headers.map do |header|
        value = row[header]
        if value.to_s =~ /^\d+\.?\d*$/
          format_number(value.to_f)
        else
          value
        end
      end
      table << "| " + values.join(" | ") + " |"
    end

    table.join("\n")
  end

  private

  def generate_histogram(values, bins = 20)
    return "No data" if values.empty?

    min_val = values.min
    max_val = values.max
    range = max_val - min_val
    bin_width = range / bins.to_f

    # Count values in each bin
    histogram = Array.new(bins, 0)
    values.each do |val|
      bin = ((val - min_val) / bin_width).floor
      bin = bins - 1 if bin >= bins
      histogram[bin] += 1
    end

    # Find max count for scaling
    max_count = histogram.max
    chart_width = 50

    # Generate chart
    chart = []
    histogram.each_with_index do |count, i|
      bar_length = (count.to_f / max_count * chart_width).round
      label = sprintf("%.3f-%.3f", min_val + i * bin_width, min_val + (i + 1) * bin_width)
      bar = "█" * bar_length
      chart << sprintf("%-15s |%-#{chart_width}s| %d", label, bar, count)
    end

    chart.join("\n")
  end

  def generate_timeline_chart(operations)
    return "No data" if operations.empty?

    # Group by time buckets
    start_time = operations.map { |op| op['timestamp'].to_f }.min
    end_time = operations.map { |op| op['timestamp'].to_f }.max
    duration = end_time - start_time

    buckets = 40
    bucket_width = duration / buckets
    timeline = Array.new(buckets) { { success: 0, failure: 0 } }

    operations.each do |op|
      bucket = ((op['timestamp'].to_f - start_time) / bucket_width).floor
      bucket = buckets - 1 if bucket >= buckets

      if op['success'] == 'true'
        timeline[bucket][:success] += 1
      else
        timeline[bucket][:failure] += 1
      end
    end

    # Generate chart
    max_ops = timeline.map { |b| b[:success] + b[:failure] }.max
    chart_height = 10

    chart = []
    chart_height.downto(0) do |level|
      line = ""
      timeline.each do |bucket|
        total = bucket[:success] + bucket[:failure]
        if total >= (level.to_f / chart_height * max_ops)
          if bucket[:failure] > 0
            line += "✗"
          else
            line += "●"
          end
        else
          line += " "
        end
      end
      chart << line
    end

    chart << "─" * buckets
    chart << "0" + " " * (buckets / 2 - 3) + "Time (s)" + " " * (buckets / 2 - 5) + sprintf("%.1f", duration)

    chart.join("\n")
  end

  def generate_error_timeline(errors)
    return "No errors" if errors.empty?

    # Group errors by time
    start_time = errors.map { |e| e['timestamp'].to_f }.min
    end_time = errors.map { |e| e['timestamp'].to_f }.max
    duration = end_time - start_time

    buckets = 60
    bucket_width = duration / buckets
    timeline = Array.new(buckets, 0)

    errors.each do |error|
      bucket = ((error['timestamp'].to_f - start_time) / bucket_width).floor
      bucket = buckets - 1 if bucket >= buckets
      timeline[bucket] += 1
    end

    # Generate sparkline
    max_errors = timeline.max
    sparkline = timeline.map do |count|
      if count == 0
        "▁"
      elsif count <= max_errors * 0.25
        "▂"
      elsif count <= max_errors * 0.5
        "▄"
      elsif count <= max_errors * 0.75
        "▆"
      else
        "█"
      end
    end.join

    "Error frequency: #{sparkline}"
  end

  def format_number(num)
    if num < 0.001
      sprintf("%.6f", num)
    elsif num < 1
      sprintf("%.4f", num)
    elsif num < 100
      sprintf("%.2f", num)
    else
      num.round.to_s
    end
  end
end

# Command-line interface
if __FILE__ == $0
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: visualize_stress_results.rb [options] file1.csv file2.csv ..."

    opts.on("-o", "--output FILE", "Output file (default: stdout)") do |file|
      options[:output] = file
    end

    opts.on("-f", "--format FORMAT", "Output format: markdown, text (default: markdown)") do |format|
      options[:format] = format
    end

    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!

  # Get CSV files
  csv_files = ARGV.empty? ? Dir.glob("*.csv") : ARGV

  if csv_files.empty?
    puts "No CSV files found. Please specify files or run in a directory with CSV files."
    exit 1
  end

  # Generate visualization
  visualizer = StressTestVisualizer.new(csv_files)
  report = visualizer.generate_report

  # Output
  if options[:output]
    File.write(options[:output], report)
    puts "Report written to: #{options[:output]}"
  else
    puts report
  end
end
