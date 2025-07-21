# try/redis_types/redistype_base_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test RedisType base functionality

# Setup test objects using existing sample classes
@sample_obj = Customer.new('customer123')
@sample_obj.custid = 'customer123'
@sample_obj.email = 'test@example.com'

## Customer has defined Redis types
Customer.redis_types.keys.include?(:timeline)
#=> true

## Customer has defined Redis types
Customer.redis_types.keys.include?(:stripe_customer)
#=> true

## Can access Redis type instances
@sample_obj.timeline.class.name
#=> "Familia::SortedSet"

## Redis types have rediskey method
@sample_obj.timeline.rediskey
#=> "v1:customer:customer123:timeline"

## Redis types are frozen after creation
@sample_obj.timeline.frozen?
#=> true

## Can access hashkey Redis type
stripe_customer = @sample_obj.stripe_customer
stripe_customer.class.name
#=> "Familia::HashKey"

## RedisType instances know their owner
@sample_obj.timeline.parent == @sample_obj
#=> true

## RedisType instances know their field name
@sample_obj.timeline.field == :timeline
#=> true

## RedisType has opts hash
@sample_obj.timeline.opts.class
#=> Hash

## RedisType responds to Redis commands
@sample_obj.timeline.respond_to?(:zadd)
#=> true

## RedisType responds to clear method
@sample_obj.timeline.respond_to?(:clear)
#=> true

## RedisType responds to destroy method
@sample_obj.timeline.respond_to?(:destroy)
#=> true

## RedisType responds to exists? method
@sample_obj.timeline.respond_to?(:exists?)
#=> true

## Can check if RedisType exists in Redis
timeline = @sample_obj.timeline
exists_before = timeline.exists?
[exists_before.class, [true, false].include?(exists_before)]
#=> [FalseClass, true]

## RedisType has size/length methods
@sample_obj.timeline.respond_to?(:size)
#=> true

## RedisType size returns integer
timeline = @sample_obj.timeline
size = timeline.size
size
#=:> Integer

## Different Redis types have type-specific methods
stripe_customer = @sample_obj.stripe_customer
stripe_customer.respond_to?(:hset)
#=> true

## Can get RedisType TTL
timeline = @sample_obj.timeline
ttl = timeline.ttl
[ttl.class, ttl >= -1]
#=> [Integer, true]

## RedisType has db method
timeline = @sample_obj.timeline
db = timeline.db
db
#=:> NilClass

## RedisType has uri method
timeline = @sample_obj.timeline
uri = timeline.uri
uri.class.name
#=> "URI::Redis"

# Cleanup
@sample_obj.destroy!
