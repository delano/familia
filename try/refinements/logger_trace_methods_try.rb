# try/refinements/logger_trace_methods_try.rb

require_relative '../helpers/test_helpers'
require 'logger'
require 'stringio'

class TestLoggerWithTrace < Logger
  include Familia::Refinements::LoggerTraceMethods
end

## Can create a logger with trace methods
output = StringIO.new
logger = TestLoggerWithTrace.new(output)
logger.respond_to?(:trace)
#=> true

## trace method logs with TRACE level
output = StringIO.new
logger = TestLoggerWithTrace.new(output)
logger.trace('Test message')
output.string
#=~> /Test message/

## trace method sets and clears severity letter
output = StringIO.new
logger = TestLoggerWithTrace.new(output)
logger.trace('Test message')
Fiber[:severity_letter]
#=> nil

## trace method accepts progname parameter
output = StringIO.new
logger = TestLoggerWithTrace.new(output)
logger.trace('MyApp') { 'Test message' }
output.string
#=~> /MyApp/
#=~> /Test message/

## trace method accepts block for message
output = StringIO.new
logger = TestLoggerWithTrace.new(output)
logger.trace { 'Block message' }
output.string
#=~> /Block message/
