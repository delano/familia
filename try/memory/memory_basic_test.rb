# try/edge_cases/memory_try.rb

require 'tempfile'
require 'json'

require_relative '../helpers/test_helpers'

class MemorySecurityTester
  def self.test_redacted_string
    results = {
      timestamp: Time.now,
      tests: []
    }

    # Test 1: Basic string search
    secret = "SENSITIVE_#{rand(999999)}"
    redacted = RedactedString.new(secret)

    # Dump all strings to file
    Tempfile.create('strings') do |f|
      ObjectSpace.each_object(String) do |str|
        f.puts str.inspect rescue nil
      end
      f.flush

      # Check if secret appears
      f.rewind
      content = f.read
      results[:tests] << {
        name: "Basic string search",
        passed: !content.include?(secret),
        details: content.include?(secret) ? "Found secret in object space" : "Secret not found"
      }
    end

    # Test 2: Memory after GC
    redacted.clear!
    GC.start(full_mark: true, immediate_sweep: true)
    sleep 0.1

    found = false
    ObjectSpace.each_object(String) do |str|
      found = true if str.include?(secret) rescue false
    end

    results[:tests] << {
      name: "After clear and GC",
      passed: !found,
      details: found ? "Secret persists after clear" : "Secret cleared"
    }

    # Test 3: Check /proc/self/mem directly
    begin
      mem_content = File.read("/proc/self/mem", 1024*1024*10) rescue ""
      results[:tests] << {
        name: "Direct memory read",
        passed: !mem_content.include?(secret),
        details: mem_content.include?(secret) ? "Found in /proc/self/mem" : "Not in readable memory"
      }
    rescue => e
      results[:tests] << {
        name: "Direct memory read",
        passed: nil,
        details: "Could not read: #{e}"
      }
    end

    puts JSON.pretty_generate(results)
  end
end

# Run the test
MemorySecurityTester.test_redacted_string
