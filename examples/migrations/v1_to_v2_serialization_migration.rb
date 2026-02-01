# examples/migrations/v1_to_v2_serialization_migration.rb
#
# frozen_string_literal: true

# V1 to V2 Serialization Migration
#
# This migration demonstrates how to upgrade Familia Horreum objects from
# v1.x serialization format (where values were stored as plain strings via
# distinguisher logic) to v2.0 format (where ALL values are JSON-encoded
# for type preservation).
#
# == Background
#
# In Familia v1.x, serialization was selective:
# - Simple types (String, Integer, Float, Symbol) → stored as plain strings via `to_s`
# - Booleans → stored as "true"/"false" strings (type info lost)
# - nil → stored as "" (empty string) or field not present
# - Hash/Array → JSON encoded
#
# In Familia v2.0, serialization is universal:
# - ALL values → JSON encoded for type preservation
# - Strings: "hello" → "\"hello\"" (JSON string with quotes)
# - Integers: 42 → "42" (JSON number, decoded as Integer)
# - Booleans: true → "true" (JSON boolean, decoded as TrueClass)
# - nil → "null" (JSON null, decoded as nil)
#
# == Migration Strategy
#
# This migration:
# 1. Scans all Horreum object keys for the specified model
# 2. Reads raw Redis values (bypassing Familia's deserializer)
# 3. Detects v1.x format values using heuristics
# 4. Re-serializes values using v2.0 JSON encoding
# 5. Writes updated values back to Redis
#
# == Usage
#
#   # Create a subclass for your specific model:
#   class CustomerSerializationMigration < V1ToV2SerializationMigration
#     self.migration_id = '20260201_120000_customer_serialization'
#     self.description = 'Migrate Customer model from v1.x to v2.0 serialization'
#
#     def prepare
#       @model_class = Customer
#       @batch_size = 100
#       super # Important: calls V1ToV2SerializationMigration's prepare
#     end
#   end
#
#   # Run dry-run first:
#   CustomerSerializationMigration.cli_run
#
#   # Run actual migration:
#   CustomerSerializationMigration.cli_run(['--run'])
#
# == Field Type Declarations
#
# For accurate type detection and conversion, override `field_types_for_model`:
#
#   def field_types_for_model
#     {
#       email: :string,
#       name: :string,
#       age: :integer,
#       balance: :float,
#       active: :boolean,
#       settings: :hash,
#       tags: :array,
#       deleted_at: :timestamp  # Integer timestamp
#     }
#   end
#
# This helps the migration correctly interpret v1.x values like:
# - "true" as boolean (not string)
# - "42" as integer (not string)
# - "{}" as hash (already JSON, no change needed)
#
require_relative '../../lib/familia'
require_relative '../../lib/familia/migration'

class V1ToV2SerializationMigration < Familia::Migration::Model
  self.migration_id = '20260201_000000_v1_to_v2_serialization_base'
  self.description = 'Base migration for v1.x to v2.0 serialization format'

  # Type mapping for v1.x → v2.0 conversions
  SUPPORTED_TYPES = %i[string integer float boolean hash array timestamp].freeze

  def prepare
    raise NotImplementedError, "Subclass must set @model_class in #prepare" unless @model_class

    @batch_size ||= 100
    @field_types = field_types_for_model

    info "Migrating #{@model_class.name} with field types: #{@field_types.keys.join(', ')}"
  end

  # Override in subclass to specify field types for your model
  #
  # @return [Hash<Symbol, Symbol>] field_name => type mapping
  #   Supported types: :string, :integer, :float, :boolean, :hash, :array, :timestamp
  def field_types_for_model
    # Default: treat all fields as strings (safest, no-op for most)
    # Override in subclass for type-aware conversion
    {}
  end

  # Override load_from_key to skip Familia's deserialization.
  # For v1→v2 migration, we work directly with raw Redis data.
  # The 'obj' returned is actually just the key itself (a String).
  def load_from_key(key)
    key # Return the key directly, we'll read raw values in process_record
  end

  def process_record(dbkey, _original_key)
    # Note: dbkey is the key string (not an object) because we override load_from_key
    # Read raw Redis values (bypass Familia deserialization)
    raw_values = read_raw_values(dbkey)

    return track_stat(:empty_records) if raw_values.empty?

    # Detect and convert v1.x values to v2.0 format
    converted = convert_v1_to_v2(raw_values)

    if converted.empty?
      debug "No fields need conversion for #{dbkey}"
      track_stat(:already_v2_format)
      return
    end

    debug "Converting #{converted.size} fields for #{dbkey}: #{converted.keys.join(', ')}"

    for_realsies_this_time? do
      write_converted_values(dbkey, converted)
    end

    track_stat(:records_updated)
    track_stat(:fields_converted, converted.size)
  end

  protected

  # Read raw string values from Redis, bypassing Familia's deserializer
  def read_raw_values(dbkey)
    redis.hgetall(dbkey)
  end

  # Write converted values back to Redis using HMSET
  def write_converted_values(dbkey, converted)
    redis.hmset(dbkey, *converted.flatten) if converted.any?
  end

  # Convert v1.x format values to v2.0 JSON-encoded format
  #
  # @param raw_values [Hash<String, String>] field_name => raw Redis value
  # @return [Hash<String, String>] field_name => converted JSON value
  def convert_v1_to_v2(raw_values)
    converted = {}

    raw_values.each do |field_name, raw_value|
      field_sym = field_name.to_sym
      field_type = @field_types[field_sym] || detect_type(raw_value)

      # Skip if already in v2.0 format
      next if already_v2_format?(raw_value, field_type)

      # Convert v1.x value to v2.0 format
      v2_value = convert_value(raw_value, field_type)

      if v2_value != raw_value
        converted[field_name] = v2_value
        track_stat("converted_#{field_type}".to_sym)
      end
    end

    converted
  end

  # Detect if a value is already in v2.0 JSON format
  #
  # v2.0 format characteristics:
  # - Strings are JSON-quoted: "\"hello\""
  # - Numbers, booleans are valid JSON: "42", "true", "false"
  # - null is explicit: "null"
  # - Hashes/Arrays are JSON objects/arrays: "{...}", "[...]"
  #
  # v1.x format characteristics:
  # - Strings are plain: "hello" (no wrapping quotes)
  # - Numbers stored as string but parsed same as JSON
  # - Booleans same as JSON but interpreted as strings
  # - Empty string "" for nil (v2 uses "null")
  def already_v2_format?(value, expected_type)
    # nil values in Ruby don't need conversion (handled elsewhere)
    return true if value.nil?

    # Empty strings in v1.x represent nil, which should be "null" in v2.0
    # So empty strings are NOT already in v2.0 format
    return false if value.empty?

    case expected_type
    when :string
      # v2.0 strings start and end with escaped quotes
      value.start_with?('"') && value.end_with?('"')

    when :integer, :float
      # Numbers look the same in both formats, but v2 JSON parses correctly
      # Can't reliably detect, so we'll skip if parseable as JSON number
      begin
        parsed = Familia::JsonSerializer.parse(value)
        parsed.is_a?(Integer) || parsed.is_a?(Float)
      rescue Familia::SerializerError
        false
      end

    when :boolean
      # Both formats store "true"/"false", but v1 parses as string
      # v2 parses as actual boolean - can't detect from storage alone
      # We need to re-serialize to ensure correct JSON format
      value == 'true' || value == 'false'

    when :hash, :array
      # Both v1 and v2 store as JSON, already compatible
      begin
        parsed = Familia::JsonSerializer.parse(value)
        (expected_type == :hash && parsed.is_a?(Hash)) ||
          (expected_type == :array && parsed.is_a?(Array))
      rescue Familia::SerializerError
        false
      end

    when :timestamp
      # Timestamps are integers, same handling as :integer
      already_v2_format?(value, :integer)

    else
      false
    end
  end

  # Convert a v1.x value to v2.0 JSON-encoded format
  #
  # @param raw_value [String] The raw Redis string value
  # @param field_type [Symbol] Expected field type
  # @return [String] JSON-encoded value for v2.0 storage
  def convert_value(raw_value, field_type)
    # Handle empty string (v1.x nil representation)
    return 'null' if raw_value == ''

    ruby_value = parse_v1_value(raw_value, field_type)
    Familia::JsonSerializer.dump(ruby_value)
  rescue StandardError => e
    warn "Failed to convert value '#{raw_value}' as #{field_type}: #{e.message}"
    track_stat(:conversion_errors)
    raw_value # Return original on error
  end

  # Parse a v1.x stored value to its Ruby type
  #
  # @param raw_value [String] The raw Redis string value
  # @param field_type [Symbol] Expected field type
  # @return [Object] The parsed Ruby value
  def parse_v1_value(raw_value, field_type)
    case field_type
    when :string
      # v1 strings are stored as-is, already correct Ruby type
      raw_value

    when :integer, :timestamp
      # v1 integers stored as string "42"
      raw_value.to_i

    when :float
      # v1 floats stored as string "3.14"
      raw_value.to_f

    when :boolean
      # v1 booleans stored as "true"/"false" strings
      raw_value == 'true'

    when :hash, :array
      # v1 complex types already JSON-encoded, parse them
      begin
        Familia::JsonSerializer.parse(raw_value)
      rescue Familia::SerializerError
        # Corrupted JSON, return empty structure
        field_type == :hash ? {} : []
      end

    else
      # Unknown type, treat as string
      raw_value
    end
  end

  # Attempt to detect the type of a value from its format
  #
  # Used when field_types_for_model doesn't specify a field type.
  # This is a heuristic and may not always be accurate.
  #
  # @param value [String] The raw Redis value
  # @return [Symbol] Detected type (defaults to :string)
  def detect_type(value)
    return :string if value.nil? || value.empty?

    # JSON object (hash)
    return :hash if value.start_with?('{') && value.end_with?('}')

    # JSON array
    return :array if value.start_with?('[') && value.end_with?(']')

    # Potential boolean
    return :boolean if %w[true false].include?(value)

    # JSON null (v2.0 format for nil)
    return :string if value == 'null'

    # Potential integer
    return :integer if value.match?(/\A-?\d+\z/)

    # Potential float
    return :float if value.match?(/\A-?\d+\.\d+\z/)

    # Already JSON-quoted string (v2.0 format)
    return :string if value.start_with?('"') && value.end_with?('"')

    # Default: plain string (v1.x format)
    :string
  end
end

# Example: Concrete migration for a User model
#
# Uncomment and customize for your application:
#
# class UserSerializationMigration < V1ToV2SerializationMigration
#   self.migration_id = '20260201_120000_user_serialization'
#   self.description = 'Migrate User model from v1.x to v2.0 serialization'
#
#   def prepare
#     @model_class = User
#     @batch_size = 100
#     super
#   end
#
#   def field_types_for_model
#     {
#       email: :string,
#       name: :string,
#       age: :integer,
#       balance: :float,
#       active: :boolean,
#       verified: :boolean,
#       login_count: :integer,
#       last_login_at: :timestamp,
#       settings: :hash,
#       roles: :array
#     }
#   end
# end

if $PROGRAM_NAME == __FILE__
  puts "V1ToV2SerializationMigration is a base class."
  puts "Create a subclass for your specific model and run that."
  puts
  puts "Example:"
  puts "  class CustomerMigration < V1ToV2SerializationMigration"
  puts "    self.migration_id = '20260201_customer_v2'"
  puts "    def prepare"
  puts "      @model_class = Customer"
  puts "      super"
  puts "    end"
  puts "  end"
  puts
  puts "  CustomerMigration.cli_run"
end
