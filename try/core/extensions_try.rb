require_relative '../helpers/test_helpers'

# Test core extensions

## String time parsing - seconds
'60s'.in_seconds
#=> 60

## String time parsing - minutes
'5m'.in_seconds
#=> 300

## String time parsing - hours
'2h'.in_seconds
#=> 7200

## String time parsing - days
'1d'.in_seconds
#=> 86_400

## String time parsing - days
'1y'.in_seconds
#=> 31536000

## Time::Units - second
1.second
#=> 1

## Time::Units - minute
1.minute
#=> 60

## Time::Units - hour
1.hour
#=> 3600

## Time::Units - day
1.day
#=> 86_400

## Time::Units - week
1.week
#=> 604_800

## Numeric extension to_ms
1000.to_ms
#=> 1000 * 1000

## Numeric extension to_bytes - single byte
1.to_bytes
#=> '1.00 B'

## Numeric extension to_bytes - kilobytes
1024.to_bytes
#=> '1.00 KiB'

## Numeric extension to_bytes - megabytes
(1024 * 1024).to_bytes
#=> '1.00 MiB'
