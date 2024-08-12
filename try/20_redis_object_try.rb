
require 'familia'
require 'familia/test_helpers'
Familia.apiversion = 'v1'


## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken', :name1
@b = Bone.new 'atoken', :name2
@a.owners.rediskey.eql?(@b.owners.rediskey)
#=> false

## Redis Objects are frozen
@a.owners.frozen?
#=> true


## Limiter#qstamp
@limiter1 = Limiter.new :requests
@limiter1.counter.qstamp(10.minutes, '%H:%M', 1302468980)
#=> '20:50'

## Redis Objects can be stored to quantized stamp suffix
@limiter1.counter.rediskey
#=> "v1:limiter:requests:counter:20:50"

## Limiter#qstamp as a number
@limiter2 = Limiter.new :requests
@limiter2.counter.qstamp(10.minutes, pattern=nil, now=1302468980)
#=> 1302468600

## Redis Objects can be stored to quantized numeric suffix. This
## tryouts is disabled b/c `RedisType#rediskey` takes no args
## and relies on the `class Limiter` definition in test_helpers.rb
## for the `:quantize` option. The quantized suffix for the Limiter
## class is `'%H:%M'` so its redis keys will always look like that.
@limiter2.counter.rediskey
##=> "v1:limiter:requests:counter:1302468600"


## Increment counter
@limiter1.counter.clear
@limiter1.counter.increment
#=> 1

## Check ttl
@limiter1.counter.ttl
#=> 3600.0

## Check ttl for a different instance
## (this exists to make sure options are cloned for each instance)
@limiter3 = Limiter.new :requests
@limiter3.counter.ttl
#=> 3600.0

## Check realttl
sleep 1 # Redis ttls are in seconds so we can't wait any less time than this (without mocking)
@limiter1.counter.realttl
#=> 3600-1
