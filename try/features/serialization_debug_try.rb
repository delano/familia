require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Test class with various field types for serialization debugging
class SerDebugWidget < Familia::Horreum
  identifier_field :widgetid
  field :widgetid
  field :name       # String
  field :count      # Integer
  field :active     # Boolean
  field :rating     # Float
  field :metadata   # Hash
  field :tags_list  # Array
  field :missing    # nil (not set)
end

# Clean slate
SerDebugWidget.instances.clear
SerDebugWidget.all.each(&:destroy!)

@w = SerDebugWidget.new(
  widgetid: 'serdebug_1',
  name: 'UK',
  count: 42,
  active: true,
  rating: 3.14,
  metadata: { color: 'red', size: 10 },
  tags_list: ['alpha', 'beta']
)

## debug_fields returns a hash keyed by field name strings
@df = @w.debug_fields
@df.is_a?(Hash)
#=> true

## debug_fields includes all persistent fields
@df.keys.sort
#=> ["active", "count", "metadata", "missing", "name", "rating", "tags_list", "widgetid"]

## String field shows correct ruby value
@df['name'][:ruby]
#=> 'UK'

## String field shows JSON-encoded stored value (double-quoted)
@df['name'][:stored]
#=> '"UK"'

## String field shows correct type
@df['name'][:type]
#=> 'String'

## Integer field shows correct ruby value
@df['count'][:ruby]
#=> 42

## Integer field shows number as stored string
@df['count'][:stored]
#=> '42'

## Integer field shows correct type
@df['count'][:type]
#=> 'Integer'

## Boolean field shows correct ruby value
@df['active'][:ruby]
#=> true

## Boolean field shows correct stored value
@df['active'][:stored]
#=> 'true'

## Boolean field shows correct type
@df['active'][:type]
#=> 'TrueClass'

## Float field shows correct ruby value
@df['rating'][:ruby]
#=> 3.14

## Float field shows correct stored value
@df['rating'][:stored]
#=> '3.14'

## Float field shows correct type
@df['rating'][:type]
#=> 'Float'

## Hash field shows correct ruby value
@df['metadata'][:ruby]
#=> { color: 'red', size: 10 }

## Hash field stored value is JSON string
@df['metadata'][:stored].is_a?(String) && @df['metadata'][:stored].include?('"color"')
#=> true

## Hash field shows correct type
@df['metadata'][:type]
#=> 'Hash'

## Array field shows correct ruby value
@df['tags_list'][:ruby]
#=> ['alpha', 'beta']

## Array field stored value is JSON string
@df['tags_list'][:stored].is_a?(String) && @df['tags_list'][:stored].include?('alpha')
#=> true

## Array field shows correct type
@df['tags_list'][:type]
#=> 'Array'

## nil field shows nil ruby value
@df['missing'][:ruby]
#=> nil

## nil field stored value is JSON null
@df['missing'][:stored]
#=> 'null'

## nil field shows NilClass type
@df['missing'][:type]
#=> 'NilClass'

## storage_inspect returns decoded fields from saved object
@w.save
@si = SerDebugWidget.storage_inspect('serdebug_1')
@si.is_a?(Hash)
#=> true

## storage_inspect raw value is the JSON-encoded string from Redis
@si['name'][:raw]
#=> '"UK"'

## storage_inspect decoded value matches ruby value
@si['name'][:decoded]
#=> 'UK'

## storage_inspect integer field decoded correctly
@si['count'][:decoded]
#=> 42

## storage_inspect boolean field decoded correctly
@si['active'][:decoded]
#=> true

## storage_inspect returns nil for nonexistent key
SerDebugWidget.storage_inspect('totally_nonexistent_widget')
#=> nil

## storage_inspect accepts full dbkey from an instance
@full_key = @w.dbkey
@si2 = SerDebugWidget.storage_inspect(@full_key)
@si2['name'][:decoded]
#=> 'UK'

# Cleanup
SerDebugWidget.instances.clear
SerDebugWidget.all.each(&:destroy!)
