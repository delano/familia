require_relative '../helpers/test_helpers'

# Test Familia refinements
group "Familia Refinements"

using Familia::FlexibleHashAccess

try "FlexibleHashAccess allows string/symbol key interchange" do
  hash = { name: "test", "email" => "test@example.com" }

  hash[:name] == "test" &&
    hash["name"] == "test" &&
    hash[:email] == "test@example.com" &&
    hash["email"] == "test@example.com"
end

try "LoggerTraceRefinement adds trace level when FAMILIA_TRACE enabled" do
  old_env = ENV['FAMILIA_TRACE']
  ENV['FAMILIA_TRACE'] = '1'

  logger = Logger.new(STDOUT)
  logger.respond_to?(:trace)
ensure
  ENV['FAMILIA_TRACE'] = old_env
end

try "FAMILIA_TRACE environment control" do
  old_env = ENV['FAMILIA_TRACE']

  ENV['FAMILIA_TRACE'] = '1'
  trace_enabled = ENV['FAMILIA_TRACE']

  ENV['FAMILIA_TRACE'] = nil
  trace_disabled = ENV['FAMILIA_TRACE']

  trace_enabled == '1' && trace_disabled.nil?
ensure
  ENV['FAMILIA_TRACE'] = old_env
end
