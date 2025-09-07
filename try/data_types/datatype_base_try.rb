# try/data_types/base_try.rb

require_relative '../helpers/test_helpers'

@limiter1 = Limiter.new :requests

## Database Types are unique per instance of a Familia class
@a = Bone.new 'atoken1', :name1
@b = Bone.new 'atoken2', :name2
p [@a.object_id, @b.object_id]
p [@a.owners.parent.class, @b.owners.parent.class]
p [@a.owners.parent.object_id, @b.owners.parent.object_id]
p [@a.owners.dbkey, @b.owners.dbkey]
p [@a.token, @b.token]
p [@a.name, @b.name]
@a.owners.dbkey.eql?(@b.owners.dbkey)
#=> false

## Database Types are frozen
@a.owners.frozen?
#=> true

## Limiter#qstamp
RefinedContext.eval_in_refined_context("@limiter1.counter.qstamp(10.minutes, '%H:%M', 1_302_468_980)")
##=> '20:50'

## Database Types can be stored to quantized stamp suffix
@limiter1.counter.dbkey
##=> "v1:limiter:requests:counter:20:50"

## Limiter#qstamp as a number
@limiter2 = Limiter.new :requests
p [@limiter1.default_expiration, @limiter2.default_expiration]
p [@limiter1.counter.parent.default_expiration, @limiter2.counter.parent.default_expiration]
RefinedContext.instance_variable_set(:@limiter2, @limiter2)
RefinedContext.eval_in_refined_context("@limiter2.counter.qstamp(10.minutes, pattern: nil, time: 1_302_468_980)")
#=> 1302468600

## Database Types can be stored to quantized numeric suffix. This
## tryouts is disabled b/c `DataType#dbkey` takes no args
## and relies on the `class Limiter` definition in test_helpers.rb
## for the `:quantize` option. The quantized suffix for the Limiter
## class is `'%H:%M'` so its dbkeys will always look like that.
@limiter2.counter.dbkey
##=> "v1:limiter:requests:counter:1302468600"

## Increment counter
@limiter1.counter.delete!
@limiter1.counter.increment
#=> 1

## Check counter default_expiration
@limiter1.counter.default_expiration
#=> 3600.0

## Check limiter default_expiration
@limiter1.default_expiration
#=> 1800.0

## Check default_expiration for a different instance
## (this exists to make sure options are cloned for each instance)
@limiter3 = Limiter.new :requests
@limiter3.counter.default_expiration
#=> 3600.0

## Check current_expiration
sleep 1 # NOTE: Mocking time would be foolish in life, but helpful here
@limiter1.counter.current_expiration
#=> 3600-1
