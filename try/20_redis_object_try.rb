
require 'familia'
require 'familia/test_helpers'
Familia.apiversion = 'v1'


## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken'
@b = Bone.new 'btoken'
@a.owners.rediskey == @b.owners.rediskey
#=> false

## Redis Objects are frozen 
@a.owners.frozen?
#=> true


## Limiter#qstamp
@limiter = Limiter.new :requests
@limiter.counter.qstamp 10.minutes, '%H:%M', 1302468980
#=> '20:50'

## Redis Objects can be stored to quantized keys
Familia.split(@limiter.counter.rediskey).size
#=> 5

## Increment counter
@limiter.counter.clear
@limiter.counter.increment
#=> 1

## Check ttl
@limiter.counter.ttl
#=> 3600

## Check realttl
sleep 2
@limiter.counter.realttl
#=> 3600-2