# try/unit/core/logging_trace_cache_try.rb
#
# frozen_string_literal: true

# Test Familia trace-enabled caching (issue #233)
#
# Familia.trace runs on hot paths; re-reading ENV['FAMILIA_TRACE'] on every
# call is wasteful. The lookup is cached after first use and only re-read when
# Familia.reset_trace! is called. This is the escape hatch tests need when they
# toggle the env var at runtime.
#
# Covers:
# - trace_enabled? reflects FAMILIA_TRACE on first evaluation
# - The result is cached (env changes are ignored until reset)
# - reset_trace! forces re-evaluation
# - Recognized truthy spellings (1, true, yes; case-insensitive)

require_relative '../../support/helpers/test_helpers'

# Setup: remember the ambient env + cache so the suite is left untouched.
@original_trace_env = ENV.fetch('FAMILIA_TRACE', nil)

## trace_enabled? is true when FAMILIA_TRACE is enabled and freshly reset
ENV['FAMILIA_TRACE'] = 'true'
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> true

## a cached true survives an env change until reset (no per-call ENV read)
ENV['FAMILIA_TRACE'] = 'false'
Familia.send(:trace_enabled?)
#=> true

## reset_trace! re-reads the env var and picks up the new value
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> false

## a cached false likewise survives an env change until reset
ENV['FAMILIA_TRACE'] = 'true'
Familia.send(:trace_enabled?)
#=> false

## reset_trace! after enabling re-reads as true
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> true

## reset_trace! returns nil (cache cleared, not yet recomputed)
Familia.reset_trace!
#=> nil

## "1" is recognized as enabled
ENV['FAMILIA_TRACE'] = '1'
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> true

## "yes" is recognized as enabled
ENV['FAMILIA_TRACE'] = 'yes'
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> true

## recognition is case-insensitive
ENV['FAMILIA_TRACE'] = 'TRUE'
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> true

## arbitrary values are treated as disabled
ENV['FAMILIA_TRACE'] = 'maybe'
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> false

## an unset FAMILIA_TRACE defaults to disabled
ENV.delete('FAMILIA_TRACE')
Familia.reset_trace!
Familia.send(:trace_enabled?)
#=> false

# Teardown: restore the ambient env var and recompute the cache from it.
if @original_trace_env.nil?
  ENV.delete('FAMILIA_TRACE')
else
  ENV['FAMILIA_TRACE'] = @original_trace_env
end
Familia.reset_trace!
