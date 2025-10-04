# try/edge_cases/memory_detailed_test_try.rb

require 'objspace'
require 'json'

require_relative '../helpers/test_helpers'

class DetailedMemoryTester
  def self.test_with_details
    ObjectSpace.trace_object_allocations_start

    secret = "SENSITIVE_#{rand(999999)}_DATA"
    puts "Testing with secret: #{secret}"
    puts "Secret object_id: #{secret.object_id}"
    puts "Secret frozen?: #{secret.frozen?}\n\n"

    # Track all string copies
    tracker = {}

    # Before creating RedactedString
    find_secret_copies(secret, "BEFORE RedactedString creation", tracker)

    # Create RedactedString
    redacted = RedactedString.new(secret)
    find_secret_copies(secret, "AFTER RedactedString creation", tracker)

    # Use expose block
    exposed_value = nil
    redacted.expose do |plain|
      exposed_value = plain.object_id
      find_secret_copies(secret, "DURING expose block", tracker)
    end
    find_secret_copies(secret, "AFTER expose block", tracker)

    # Clear and GC
    redacted.clear!
    original_secret = secret
    secret = nil  # Remove our reference
    GC.start(full_mark: true, immediate_sweep: true)

    find_secret_copies(original_secret, "AFTER clear! and GC", tracker)

    # Final report
    puts "\n" + "="*60
    puts "FINAL ANALYSIS"
    puts "="*60

    remaining_copies = []
    ObjectSpace.each_object(String) do |str|
      begin
        if str.include?(original_secret)
          remaining_copies << {
            object_id: str.object_id,
            size: str.bytesize,
            encoding: str.encoding.name,
            frozen: str.frozen?,
            tainted: (str.tainted? rescue "N/A"),
            value_preview: str[0..50]
          }
        end
      rescue => e
        # Skip strings that can't be accessed
      end
    end

    if remaining_copies.empty?
      puts "✅ SUCCESS: No copies found in memory!"
    else
      puts "❌ FAILURE: #{remaining_copies.size} copies still in memory:"
      remaining_copies.each do |copy|
        puts "\n  Object ID: #{copy[:object_id]}"
        puts "  Size: #{copy[:size]} bytes"
        puts "  Frozen: #{copy[:frozen]}"
        puts "  Encoding: #{copy[:encoding]}"
      end
    end

    # Show memory stats
    puts "\n" + "="*60
    puts "MEMORY STATISTICS"
    puts "="*60
    puts "Total strings in ObjectSpace: #{ObjectSpace.each_object(String).count}"
    puts "GC count: #{GC.count}"
    puts "GC stat: #{GC.stat[:heap_live_slots]} live slots"

    tracker
  end

  private

  def self.find_secret_copies(secret, phase, tracker)
    copies = []

    ObjectSpace.each_object(String) do |str|
      begin
        if str.include?(secret)
          copies << {
            object_id: str.object_id,
            frozen: str.frozen?,
            source: ObjectSpace.allocation_sourcefile(str),
            line: ObjectSpace.allocation_sourceline(str)
          }
        end
      rescue => e
        # Some strings might not be accessible
      end
    end

    tracker[phase] = copies

    puts "#{phase}: Found #{copies.size} copies"
    copies.each do |copy|
      source_info = copy[:source] ? "#{copy[:source]}:#{copy[:line]}" : "unknown source"
      puts "  - Object #{copy[:object_id]} (frozen: #{copy[:frozen]}) from #{source_info}"
    end
    puts ""
  end
end

# Run the detailed test
DetailedMemoryTester.test_with_details
