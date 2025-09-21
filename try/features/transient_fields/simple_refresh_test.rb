
require_relative '../../helpers/test_helpers'

Familia.debug = false
Familia.dbclient.flushdb

# Use existing Customer class (should work)
service = Customer.new('refresh-test-customer')
puts "Created customer: #{service.class}"
puts "Customer identifier: #{service.identifier}"

# Add a transient field for testing
class Customer
  transient_field :temp_data
end

# UnsortedSet some values
service.name = 'Test Customer'
service.temp_data = 'secret-info'

puts "Before save:"
puts "  name: #{service.name.inspect}"
puts "  temp_data: #{service.temp_data.inspect}"
puts "  temp_data class: #{service.temp_data.class}"

# Save to database
result = service.save
puts "Save result: #{result}"

puts "Before refresh:"
puts "  name: #{service.name.inspect}"
puts "  temp_data: #{service.temp_data.inspect}"
puts "  temp_data nil?: #{service.temp_data.nil?}"

# Refresh should reset transient field to nil but keep persistent field
service.refresh!
puts "After refresh:"
puts "  name: #{service.name.inspect}"
puts "  temp_data: #{service.temp_data.inspect}"
puts "  temp_data nil?: #{service.temp_data.nil?}"

# Verify that the refresh! reset worked as expected
if service.temp_data.nil? && service.name == 'Test Customer'
  puts "SUCCESS: refresh! properly reset transient field while preserving persistent field"
else
  puts "FAILED: refresh! did not work as expected"
end

service.destroy!
puts "Test completed"
