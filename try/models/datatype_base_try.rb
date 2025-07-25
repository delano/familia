# try/datatypes/datatype_base_try.rb

# Test DataType base functionality

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

@sample_obj = Customer.new(custid: 'customer123', email: 'test@example.com')

## Customer has defined Database types
Customer.related_fields.keys.include?(:timeline)
#=> true

## Customer has defined Database types
Customer.related_fields.keys.include?(:stripe_customer)
#=> true

## Can access Database type instances
@sample_obj.timeline
#=:> Familia::SortedSet

## Database types have dbkey method
@sample_obj.timeline.dbkey
#=> "customer:customer123:timeline"

## Database types are frozen after creation
@sample_obj.timeline.frozen?
#=> true

## Can access hashkey Database type
@sample_obj ||= Customer.new(custid: 'customer123', email: 'test@example.com')
stripe_customer = @sample_obj.stripe_customer
stripe_customer.class.name
#=> "Familia::HashKey"

## DataType instances know their owner
@sample_obj.timeline.parent == @sample_obj
#=> true

## DataType instances know their field name
@sample_obj.timeline.keystring
#=> :timeline

## DataType has opts hash
@sample_obj.timeline.opts.class
#=> Hash

## DataType responds to Familia's modified Database commands
@sample_obj.timeline
#=/=> _.respond_to?(:zadd)
#==> _.respond_to?(:add)
#==> _.respond_to?(:clear)
#==> _.respond_to?(:exists?)
#=/=> _.respond_to?(:destroy!)

## Can check if DataType exists in Redis
timeline = @sample_obj.timeline
exists_before = timeline.exists?
[exists_before.class, [true, false].include?(exists_before)]
#=> [FalseClass, true]

## DataType has size/length methods
@sample_obj.timeline.respond_to?(:size)
#=> true

## DataType size returns integer
timeline = @sample_obj.timeline
timeline.size
#=:> Integer

## Different Database types have type-specific methods
stripe_customer = @sample_obj.stripe_customer
stripe_customer
#=/=> _.respond_to?(:hset)
#==> _.respond_to?(:put)
#==> _.respond_to?(:store)
#==> _.respond_to?(:[]=)

## Can get DataType default expiration
timeline = @sample_obj.timeline
default_expiration = timeline.default_expiration
[default_expiration.class, default_expiration >= -1]
#=> [Integer, true]

## DataType has logical_database method
timeline = @sample_obj.timeline
db = timeline.logical_database
db
#=:> NilClass

## DataType has uri method
timeline = @sample_obj.timeline
timeline.uri
#=:> URI::Generic

# Cleanup
@sample_obj.destroy!
