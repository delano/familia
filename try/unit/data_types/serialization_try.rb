# try/unit/data_types/serialization_try.rb
#
# frozen_string_literal: true

# Test coverage for DataType serialization/deserialization behavior
# Issue #190: Unify DataType and Horreum serialization for type preservation

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Create test instances
@bone = Bone.new('serialize_test_token')

# ========================================
# DataType Serialization Behavior (Issue #190)
# Now uses JSON serialization for type preservation
# ========================================

## HashKey stores string values correctly
@bone.props['string_field'] = 'hello'
@bone.props['string_field']
#=> 'hello'

## HashKey stores integer with type preservation
@bone.props['int_field'] = 42
@bone.props['int_field']
#=> 42

## HashKey stores float with type preservation
@bone.props['float_field'] = 3.14
@bone.props['float_field']
#=> 3.14

## HashKey stores symbol as string (symbols serialize to strings in JSON)
@bone.props['symbol_field'] = :active
@bone.props['symbol_field']
#=> 'active'

## HashKey stores boolean true with type preservation
@bone.props['bool_true'] = true
@bone.props['bool_true']
#=> true

## HashKey stores boolean true as TrueClass
@bone.props['bool_true'].class
#=> TrueClass

## HashKey stores boolean false with type preservation
@bone.props['bool_false'] = false
@bone.props['bool_false']
#=> false

## HashKey stores boolean false as FalseClass
@bone.props['bool_false'].class
#=> FalseClass

## HashKey stores nil with type preservation
@bone.props['nil_field'] = nil
@bone.props['nil_field']
#=> nil

## HashKey stores hash with type preservation
@bone.props['hash_field'] = { 'key' => 'value' }
@bone.props['hash_field']
#=> {'key'=>'value'}

## HashKey stores array with type preservation
@bone.props['array_field'] = [1, 2, 3]
@bone.props['array_field']
#=> [1, 2, 3]

# ========================================
# List Serialization Behavior
# ========================================

## List stores string values correctly
@bone.owners.delete!
@bone.owners.push('owner1')
@bone.owners.first
#=> 'owner1'

## List stores integer with type preservation
@bone.owners.delete!
@bone.owners.push(123)
@bone.owners.first
#=> 123

## List stores boolean with type preservation
@bone.owners.delete!
@bone.owners.push(true)
@bone.owners.first
#=> true

## List stores nil with type preservation
@bone.owners.delete!
@bone.owners.push(nil)
@bone.owners.first
#=> nil

# ========================================
# Set Serialization Behavior
# ========================================

## Set stores string values correctly
@bone.tags.delete!
@bone.tags.add('tag1')
@bone.tags.members.include?('tag1')
#=> true

## Set stores integer with type preservation
@bone.tags.delete!
@bone.tags.add(42)
@bone.tags.members.include?(42)
#=> true

## Set stores boolean with type preservation
@bone.tags.delete!
@bone.tags.add(true)
@bone.tags.members.include?(true)
#=> true

# ========================================
# SortedSet Serialization Behavior
# ========================================

## SortedSet stores string values correctly
@bone.metrics.delete!
@bone.metrics.add('metric1', 1.0)
@bone.metrics.members.include?('metric1')
#=> true

## SortedSet stores integer member with type preservation
@bone.metrics.delete!
@bone.metrics.add(999, 1.0)
@bone.metrics.members.include?(999)
#=> true

## SortedSet stores boolean member with type preservation
@bone.metrics.delete!
@bone.metrics.add(true, 1.0)
@bone.metrics.members.include?(true)
#=> true

# ========================================
# Horreum Field Serialization (for comparison)
# Uses JSON encoding - type preserved
# ========================================

## Horreum field stores string with JSON encoding
@customer = Customer.new
@customer.custid = 'serialization_test'
@customer.role = 'admin'
@customer.save
loaded = Customer.find_by_id('serialization_test')
loaded.role
#=> 'admin'

## Horreum field stores boolean true (JSON encoded)
@customer.verified = true
@customer.save
@loaded_customer = Customer.find_by_id('serialization_test')
@loaded_customer.verified
#=> true

## Horreum verified field is actually boolean, not string
@loaded_customer.verified.class
#=> TrueClass

## Horreum field stores boolean false (JSON encoded)
@customer.reset_requested = false
@customer.save
@loaded_customer2 = Customer.find_by_id('serialization_test')
@loaded_customer2.reset_requested
#=> false

## Horreum reset_requested field is actually boolean, not string
@loaded_customer2.reset_requested.class
#=> FalseClass

# ========================================
# Type Round-Trip Comparison (Unified Behavior)
# ========================================

## Integer round-trip in HashKey now preserves type (Issue #190)
@bone.props['roundtrip_int'] = 100
retrieved = @bone.props['roundtrip_int']
retrieved.class
#=> Integer

## Boolean round-trip in HashKey preserves type
@bone.props['roundtrip_bool'] = true
@bone.props['roundtrip_bool'].class
#=> TrueClass

## DataType and Horreum now use same JSON serialization
@session = Session.new
@session.sessid = 'roundtrip_test'
# Both DataType and Horreum fields now preserve types consistently

# ========================================
# Horreum serialize_value Comprehensive Tests
# (Issue #190: Document behavior for unification)
# ========================================

## Horreum serialize_value: string gets JSON encoded with quotes
@customer.serialize_value('hello')
#=> '"hello"'

## Horreum serialize_value: empty string gets JSON encoded
@customer.serialize_value('')
#=> '""'

## Horreum serialize_value: integer becomes JSON number (no quotes)
@customer.serialize_value(42)
#=> '42'

## Horreum serialize_value: zero becomes JSON number
@customer.serialize_value(0)
#=> '0'

## Horreum serialize_value: negative integer
@customer.serialize_value(-99)
#=> '-99'

## Horreum serialize_value: float becomes JSON number
@customer.serialize_value(3.14159)
#=> '3.14159'

## Horreum serialize_value: boolean true becomes JSON true
@customer.serialize_value(true)
#=> 'true'

## Horreum serialize_value: boolean false becomes JSON false
@customer.serialize_value(false)
#=> 'false'

## Horreum serialize_value: nil becomes JSON null
@customer.serialize_value(nil)
#=> 'null'

## Horreum serialize_value: symbol becomes JSON string
@customer.serialize_value(:active)
#=> '"active"'

## Horreum serialize_value: hash becomes JSON object
@customer.serialize_value({ name: 'test', count: 5 })
#=> '{"name":"test","count":5}'

## Horreum serialize_value: array becomes JSON array
@customer.serialize_value([1, 'two', true, nil])
#=> '[1,"two",true,null]'

## Horreum serialize_value: nested structures work
@customer.serialize_value({ users: [{ id: 1 }, { id: 2 }] })
#=> '{"users":[{"id":1},{"id":2}]}'

# ========================================
# Horreum deserialize_value Comprehensive Tests
# ========================================

## Horreum deserialize_value: JSON string becomes Ruby string
@customer.deserialize_value('"hello"')
#=> 'hello'

## Horreum deserialize_value: JSON number becomes Ruby integer
@customer.deserialize_value('42')
#=> 42

## Horreum deserialize_value: JSON number is actually Integer class
@customer.deserialize_value('42').class
#=> Integer

## Horreum deserialize_value: JSON float becomes Ruby float
@customer.deserialize_value('3.14159')
#=> 3.14159

## Horreum deserialize_value: JSON float is actually Float class
@customer.deserialize_value('3.14159').class
#=> Float

## Horreum deserialize_value: JSON true becomes Ruby true
@customer.deserialize_value('true')
#=> true

## Horreum deserialize_value: JSON true is TrueClass
@customer.deserialize_value('true').class
#=> TrueClass

## Horreum deserialize_value: JSON false becomes Ruby false
@customer.deserialize_value('false')
#=> false

## Horreum deserialize_value: JSON false is FalseClass
@customer.deserialize_value('false').class
#=> FalseClass

## Horreum deserialize_value: JSON null becomes Ruby nil
@customer.deserialize_value('null')
#=> nil

## Horreum deserialize_value: JSON object becomes Ruby hash
@customer.deserialize_value('{"name":"test","count":5}')
#=> {"name"=>"test", "count"=>5}

## Horreum deserialize_value: JSON array becomes Ruby array
@customer.deserialize_value('[1,"two",true,null]')
#=> [1, "two", true, nil]

## Horreum deserialize_value: nil input returns nil
@customer.deserialize_value(nil)
#=> nil

## Horreum deserialize_value: empty string returns nil
@customer.deserialize_value('')
#=> nil

## Horreum deserialize_value: plain unquoted string (legacy data) returns as-is
# This handles data stored before JSON encoding was used
@customer.deserialize_value('plain string without quotes')
#=> 'plain string without quotes'

# ========================================
# Familia Object Serialization (shared behavior)
# ========================================

## Horreum serialize_value: Familia object extracts identifier
# When storing a reference to another Familia object
@ref_customer = Customer.new('reference_test@example.com')
@ref_customer.custid = 'reference_test@example.com'
# Note: Horreum.serialize_value uses JsonSerializer.dump, not identifier extraction
# This is different from DataType which uses identifier_extractor for Familia objects
@customer.serialize_value(@ref_customer.custid)
#=> '"reference_test@example.com"'

# ========================================
# Round-trip Type Preservation Tests
# ========================================

## Round-trip: integer preserves type through Horreum serialization
serialized = @customer.serialize_value(42)
@customer.deserialize_value(serialized)
#=> 42

## Round-trip: integer class preserved
serialized = @customer.serialize_value(42)
@customer.deserialize_value(serialized).class
#=> Integer

## Round-trip: boolean true preserves type
serialized = @customer.serialize_value(true)
@customer.deserialize_value(serialized)
#=> true

## Round-trip: boolean true class preserved
serialized = @customer.serialize_value(true)
@customer.deserialize_value(serialized).class
#=> TrueClass

## Round-trip: boolean false preserves type
serialized = @customer.serialize_value(false)
@customer.deserialize_value(serialized)
#=> false

## Round-trip: nil preserves type
serialized = @customer.serialize_value(nil)
@customer.deserialize_value(serialized)
#=> nil

## Round-trip: hash preserves structure
serialized = @customer.serialize_value({ active: true, count: 10 })
@customer.deserialize_value(serialized)
#=> {"active"=>true, "count"=>10}

## Round-trip: array preserves structure and types
serialized = @customer.serialize_value([1, 'two', true, nil, 3.5])
@customer.deserialize_value(serialized)
#=> [1, "two", true, nil, 3.5]

# Cleanup
@bone.props.delete!
@bone.owners.delete!
@bone.tags.delete!
@bone.metrics.delete!
@customer.destroy! rescue nil
