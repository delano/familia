# try/support/memory/memory_search_for_string.rb
#
# frozen_string_literal: true

# try/edge_cases/search_memory_for_string_try.rb

require 'objspace'

require_relative '../helpers/test_helpers'

# Enable object space tracking
ObjectSpace.trace_object_allocations_start

def search_memory_for_string(target)
  found_locations = []

  ObjectSpace.each_object(String) do |str|
    begin
      if str.include?(target)
        found_locations << {
          value: str[0..100], # First 100 chars
          object_id: str.object_id,
          source: ObjectSpace.allocation_sourcefile(str),
          line: ObjectSpace.allocation_sourceline(str),
          frozen: str.frozen?
        }
      end
    rescue => e
      # Some strings might not be accessible
    end
  end

  found_locations
end

# Test scenario
secret = "SUPER_SECRET_API_KEY_12345"
puts "Testing with secret: #{secret}"

# Create RedactedString
redacted = RedactedString.new(secret)
puts "Created RedactedString"

# Force GC to see if copies persist
GC.start(full_mark: true, immediate_sweep: true)

# Search memory
puts "\n=== Memory search BEFORE expose ==="
found = search_memory_for_string("SUPER_SECRET_API_KEY")
found.each do |location|
  puts "Found at object_id: #{location[:object_id]}"
  puts "  Value: #{location[:value]}"
  puts "  Source: #{location[:source]}:#{location[:line]}"
  puts "  Frozen: #{location[:frozen]}"
end

# Use expose
redacted.expose do |plain|
  puts "\nInside expose block, plain = [REDACTED for display]"

  # Search during expose
  puts "\n=== Memory search DURING expose ==="
  found = search_memory_for_string("SUPER_SECRET_API_KEY")
  puts "Found #{found.size} instances"
end

# After expose
GC.start(full_mark: true, immediate_sweep: true)
puts "\n=== Memory search AFTER expose ==="
found = search_memory_for_string("SUPER_SECRET_API_KEY")
found.each do |location|
  puts "Found at object_id: #{location[:object_id]}"
  puts "  Value: #{location[:value]}"
end

# Also check with marshal dump
puts "\n=== Checking Marshal dump ==="
begin
  marshaled = Marshal.dump(ObjectSpace.each_object.to_a)
  if marshaled.include?("SUPER_SECRET_API_KEY")
    puts "❌ Secret found in Marshal dump!"
  else
    puts "✅ Secret not found in Marshal dump"
  end
rescue => e
  puts "Marshal failed: #{e}"
end
