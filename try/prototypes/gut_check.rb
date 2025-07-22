#!/usr/bin/env ruby
# gut_check.rb - Simple performance gut-check
#
# Just runs pool_siege.rb --quick and shows if it's fast enough.
# No complex profiling, no JSON files, no folders to understand.

puts "🏃 Performance gut-check..."

# Run pool_siege.rb --quick in quiet mode
start_time = Time.now
result = `ruby pool_siege.rb --quick --quiet 2>&1`
exit_code = $?.exitstatus
end_time = Time.now

elapsed = end_time - start_time

# Simple check: should complete quickly and successfully
if exit_code == 0 && elapsed < 2.0
  puts "🟢 GOOD - Completed in #{elapsed.round(2)}s"
else
  puts "🔴 PROBLEM - Took #{elapsed.round(2)}s or failed"
  puts "Output:" unless result.strip.empty?
  puts result.strip unless result.strip.empty?
  exit 1
end
