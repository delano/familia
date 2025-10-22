# try/unit/core/middleware_detailed_debug_try.rb
#
# Detailed debugging of middleware registration

require_relative '../../../lib/familia'

Familia.uri = 'redis://127.0.0.1:2525'

## Check initial state
puts "Initial state:"
puts "  @middleware_registered: #{Familia.instance_variable_get(:@middleware_registered).inspect}"
puts "  @enable_database_counter: #{Familia.instance_variable_get(:@enable_database_counter).inspect}"
puts "  @enable_database_logging: #{Familia.instance_variable_get(:@enable_database_logging).inspect}"

# Enable counter
puts "\nEnabling counter..."
Familia.enable_database_counter = true

## After counter
puts "After enabling counter:"
puts "  @middleware_registered: #{Familia.instance_variable_get(:@middleware_registered).inspect}"
puts "  @enable_database_counter: #{Familia.instance_variable_get(:@enable_database_counter).inspect}"

# Enable logging
puts "\nEnabling logging..."
Familia.enable_database_logging = true

## After logging
puts "After enabling logging:"
puts "  @middleware_registered: #{Familia.instance_variable_get(:@middleware_registered).inspect}"
puts "  @enable_database_logging: #{Familia.instance_variable_get(:@enable_database_logging).inspect}"

# Try to capture commands
puts "\nTrying to capture commands..."
DatabaseLogger.clear_commands
@dbclient = Familia.dbclient
@commands = DatabaseLogger.capture_commands do
  @dbclient.set("test_key", "test_value")
end

puts "Commands captured: #{@commands.inspect}"
puts "Commands size: #{@commands&.size || 'nil'}"

## Expected to work but may not
@commands&.size || 0
#=> 1

# Cleanup
DatabaseLogger.clear_commands
