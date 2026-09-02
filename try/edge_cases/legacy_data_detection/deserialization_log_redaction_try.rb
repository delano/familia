# try/edge_cases/legacy_data_detection/deserialization_log_redaction_try.rb
#
# frozen_string_literal: true

# Deserialization failure logs must not leak the stored value (#407)
#
# When deserialize_value falls back to returning the raw string (legacy plain
# strings, corrupted JSON), it logs at ERROR and notifies instrumentation error
# hooks. Those values are precisely the ones the library does not understand,
# which can include raw ciphertext migrated from older schemes, so the message
# and the default structured context must carry no bytes of the value. A
# bounded 50-char preview is only included when Familia.debug? is on; the
# byte length is always reported.

require_relative '../../../lib/familia'
require 'logger'
require 'stringio'

@original_logger = Familia.instance_variable_get(:@logger)
@original_debug = Familia.debug?
@marker = 'TAIL-SECRET-MARKER'
@legacy_value = ('x' * 150) + @marker
@corrupted_value = "{#{'y' * 150}#{@marker}"

def capture_log
  @log_output = StringIO.new
  Familia.instance_variable_set(:@logger, Logger.new(@log_output))
  Familia.instance_variable_get(:@logger).level = Logger::DEBUG
end

def log_content
  @log_output.rewind
  @log_output.read
end

# Minimal model whose fields are fed hand-crafted stored values
class RedactionModel < Familia::Horreum
  identifier_field :test_id
  field :test_id
  field :data
end

@model = RedactionModel.new(test_id: 'redaction1')
Familia.debug = false

## Legacy plain string is returned unchanged
capture_log
@result = @model.deserialize_value(@legacy_value, field_name: :data)
@result
#=> @legacy_value

## Legacy string log line names the classification
log_content
#=~> /Legacy plain string in .*RedactionModel#data \(/

## Legacy string log line does not contain the tail of the value
log_content.include?(@marker)
#=> false

## Legacy string log line does not contain any value preview by default
log_content.include?('value_preview')
#=> false

## Legacy string log line reports the byte length of the value
log_content
#=~> /value_length=168\b/

## Legacy string log line reports the error type
log_content
#=~> /error_type=legacy_string/

## Corrupted JSON is returned unchanged
capture_log
@result = @model.deserialize_value(@corrupted_value, field_name: :data)
@result
#=> @corrupted_value

## Corrupted JSON log line names the classification
log_content
#=~> /Corrupted JSON in .*RedactionModel#data \(/

## Corrupted JSON log line does not contain the tail of the value
log_content.include?(@marker)
#=> false

## Corrupted JSON log line does not contain the leading value bytes either
log_content.include?('yyyyyyyy')
#=> false

## Corrupted JSON log line reports the byte length and error type
log_content
#=~> /error_type=corrupted_json .*value_length=169\b/

## Debug mode includes a bounded value preview
Familia.debug = true
capture_log
@model.deserialize_value(@legacy_value, field_name: :data)
log_content
#=~> /value_preview=x{50}(\s|$)/

## Debug mode preview still excludes the tail of the value
log_content.include?(@marker)
#=> false

## Debug mode is restored to its previous setting
Familia.debug = @original_debug
Familia.debug = false
Familia.debug?
#=> false

## Instrumentation error hooks receive a message without value bytes
@recorded = []
@hook = proc { |error, ctx| @recorded << [error.message, ctx] }
Familia::Instrumentation.on_error(&@hook)
capture_log
@model.deserialize_value(@legacy_value, field_name: :data)
@message, @ctx = @recorded.last
@message.include?(@marker)
#=> false

## Instrumentation error message names the classification and context
@message
#=~> /\ALegacy plain string in .*RedactionModel#data \(/

## Instrumentation error context classifies the failure
[@ctx[:error_type], @ctx[:operation], @ctx[:field]]
#=> [:legacy_string, :deserialization, :data]

## Instrumentation error context carries the value length as an Integer
@ctx[:value_length]
#=> 168

## Instrumentation error context never carries a value preview
@ctx.key?(:value_preview)
#=> false

## Instrumentation error hook is unregistered
Familia::Instrumentation.instance_variable_get(:@hooks)[:error].delete(@hook)
Familia::Instrumentation.instance_variable_get(:@hooks)[:error].include?(@hook)
#=> false

# Teardown
Familia.debug = @original_debug
Familia.instance_variable_set(:@logger, @original_logger)
