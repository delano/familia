# try/edge_cases/legacy_data_detection/deserialization_edge_cases_try.rb
#
# frozen_string_literal: true

# Edge case tests for deserialize_value with legacy data detection
#
# Tests the nuanced deserialization that distinguishes between:
# - Corrupted JSON (data that looks like JSON but fails to parse)
# - Legacy plain strings (data that was never JSON)
# - Valid JSON data

require_relative '../../../lib/familia'
require 'logger'
require 'stringio'

# Capture log output for verification
@log_output = StringIO.new
@original_logger = Familia.instance_variable_get(:@logger)
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG

class TestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id
  field :data
end

@model = TestModel.new(test_id: "test1")

## Valid JSON number deserializes correctly
@result = @model.deserialize_value("123", field_name: :data)
@result
#=> 123

## Valid JSON boolean deserializes correctly
@result = @model.deserialize_value("true", field_name: :data)
@result
#=> true

## Valid JSON string deserializes correctly
@result = @model.deserialize_value('"hello"', field_name: :data)
@result
#=> "hello"

## Valid JSON array deserializes correctly
@result = @model.deserialize_value('[1,2,3]', field_name: :data)
@result
#=> [1, 2, 3]

## Valid JSON object deserializes correctly
@result = @model.deserialize_value('{"key":"value"}', field_name: :data)
@result
#=> {"key"=>"value"}

## Plain string (legacy data) returns as-is
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value("plain text", field_name: :data)
@result
#=> "plain text"

## Legacy data logs at debug level
@log_output.rewind
@log_content = @log_output.read
puts "LOG CONTENT: #{@log_content.inspect}" if ENV['DEBUG']
@log_content
#=~> /Legacy plain string/

## Corrupted JSON starting with { logs error
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value("{broken", field_name: :data)
@result
#=> "{broken"

## Corrupted JSON logs at error level
@log_output.rewind
@log_content = @log_output.read
puts "LOG CONTENT: #{@log_content.inspect}" if ENV['DEBUG']
@log_content.match?(/Corrupted JSON/)
#=> true

## Corrupted JSON starting with [ logs error
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value("[1,2,", field_name: :data)
@result
#=> "[1,2,"

## Corrupted array logs at error level
@log_output.rewind
@log_content = @log_output.read
@log_content.match?(/Corrupted JSON/)
#=> true

## Corrupted JSON starting with quote logs error
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value('"unterminated', field_name: :data)
@result
#=> '"unterminated'

## Unterminated string logs at error level
@log_output.rewind
@log_content = @log_output.read
@log_content.match?(/Corrupted JSON/)
#=> true

## Corrupted boolean-like value logs error
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value("true123", field_name: :data)
@result
#=> "true123"

## Plain text starting with 'true' is legacy data
@log_output.rewind
@log_content = @log_output.read
@log_content
#=~> /Legacy plain string/

## Field name context appears in error messages
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value("{broken", field_name: :important_field)
@log_output.rewind
@log_content = @log_output.read
@log_content.match?(/TestModel#important_field/)
#=> true

## dbkey context appears in error messages when available
@model.save
@log_output = StringIO.new
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG
@result = @model.deserialize_value("{broken", field_name: :data)
@log_output.rewind
@log_content = @log_output.read
@log_content.match?(/#{Regexp.escape(@model.dbkey)}/)
#=> true

## Empty string returns nil
@result = @model.deserialize_value("", field_name: :data)
@result
#=> nil

## nil returns nil
@result = @model.deserialize_value(nil, field_name: :data)
@result
#=> nil

## JSON null deserializes to nil
@result = @model.deserialize_value("null", field_name: :data)
@result
#=> nil

## Symbolize option works with hash keys
@result = @model.deserialize_value('{"name":"test"}', symbolize: true, field_name: :data)
@result.keys.first.class
#=> Symbol

## Default keeps string keys
@result = @model.deserialize_value('{"name":"test"}', field_name: :data)
@result.keys.first.class
#=> String

# Teardown
Familia.instance_variable_set(:@logger, @original_logger)
