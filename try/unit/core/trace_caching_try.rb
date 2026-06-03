# try/unit/core/trace_caching_try.rb
#
# frozen_string_literal: true

# Test Familia trace_enabled? caching and reset_trace! escape hatch.
#
# trace_enabled? caches the FAMILIA_TRACE lookup so trace sites don't re-read
# ENV on every call. reset_trace! clears the cache so the next call re-reads
# the environment (used by tests that mutate FAMILIA_TRACE).

require_relative '../../support/helpers/test_helpers'

@original_trace = ENV.fetch('FAMILIA_TRACE', nil)

## reset_trace! returns nil
Familia.reset_trace!
#=> nil

## trace_enabled? reads FAMILIA_TRACE after reset_trace!
ENV['FAMILIA_TRACE'] = 'true'
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> true

## trace_enabled? caches the value; mid-flight ENV change is not seen until reset
ENV['FAMILIA_TRACE'] = 'false'
Familia.reset_trace!
first = Familia.send(:trace_enabled?)   # caches false
ENV['FAMILIA_TRACE'] = 'true'
cached = Familia.send(:trace_enabled?)  # still false (cached)
Familia.reset_trace!
refreshed = Familia.send(:trace_enabled?) # re-reads -> true
[first, cached, refreshed]
#=> [false, false, true]

## trace_enabled? recognizes 1/yes as truthy after reset
ENV['FAMILIA_TRACE'] = 'yes'
Familia.reset_trace!
yes_result = Familia.send(:trace_enabled?)
ENV['FAMILIA_TRACE'] = '1'
Familia.reset_trace!
one_result = Familia.send(:trace_enabled?)
[yes_result, one_result]
#=> [true, true]

## trace_enabled? defaults to false when FAMILIA_TRACE is unset
ENV.delete('FAMILIA_TRACE')
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> false

# Teardown: restore original FAMILIA_TRACE and cache
if @original_trace.nil?
  ENV.delete('FAMILIA_TRACE')
else
  ENV['FAMILIA_TRACE'] = @original_trace
end
Familia.reset_trace!
