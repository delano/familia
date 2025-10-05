# try/unit/core/familia_logger_try.rb

require_relative '../../support/helpers/test_helpers'
require 'logger'
require 'stringio'

## FamiliaLogger has trace method
logger = Familia::FamiliaLogger.new(StringIO.new)
logger.respond_to?(:trace)
#=> true

## trace method logs with TRACE level
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.trace('Test message')
output.string
#=~> /Test message/

## FamiliaLogger has TRACE constant
Familia::FamiliaLogger::TRACE
#=> 0

## trace method accepts progname parameter
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.trace('MyApp') { 'Test message' }
output.string
#=~> /MyApp/
#=~> /Test message/

## trace method accepts block for message
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.trace { 'Block message' }
output.string
#=~> /Block message/

## LogFormatter properly formats TRACE messages
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.formatter = Familia::LogFormatter.new
logger.trace('Trace test')
output.string
#=~> /^T,/

## Nested trace calls preserve TRACE context
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.formatter = Familia::LogFormatter.new
logger.trace do
  logger.trace('Inner trace message')
  'Outer trace message'
end
output.string.lines.size
#=> 2

## Nested trace inner message formatted as TRACE
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.formatter = Familia::LogFormatter.new
logger.trace do
  logger.trace('Inner trace message')
  'Outer trace message'
end
output.string.lines[0]
#=~> /^T,.*Inner trace message/

## Nested trace outer message formatted as TRACE
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.formatter = Familia::LogFormatter.new
logger.trace do
  logger.trace('Inner trace message')
  'Outer trace message'
end
output.string.lines[1]
#=~> /^T,.*Outer trace message/

## Nested trace calls clean up context for subsequent debug calls
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.formatter = Familia::LogFormatter.new
logger.trace do
  logger.trace('Inner trace')
  'Outer trace'
end
logger.debug('After nested traces')
output.string.lines.size
#=> 3

## Debug call after nested traces formatted as DEBUG not TRACE
output = StringIO.new
logger = Familia::FamiliaLogger.new(output)
logger.level = Familia::FamiliaLogger::TRACE
logger.formatter = Familia::LogFormatter.new
logger.trace do
  logger.trace('Inner trace')
  'Outer trace'
end
logger.debug('After nested traces')
output.string.lines[2]
#=~> /^D,.*After nested traces/
