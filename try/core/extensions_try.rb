require_relative '../helpers/test_helpers'

# Test core extensions
group 'Core Extensions'

try 'String time parsing with in_seconds' do
  '60s'.in_seconds == 60 &&
    '5m'.in_seconds == 300 &&
    '2h'.in_seconds == 7200 &&
    '1d'.in_seconds == 86_400
end

try 'Time::Units conversions' do
  1.second == 1 &&
    1.minute == 60 &&
    1.hour == 3600 &&
    1.day == 86_400 &&
    1.week == 604_800
end

try 'Numeric extensions to_ms and to_bytes' do
  1000.to_ms == 1000 &&
    1.to_bytes == 1 &&
    1024.to_bytes == '1.0 KiB' &&
    (1024 * 1024).to_bytes == '1.0 MiB'
end
