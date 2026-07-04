# try/investigation/process_memory_leak_proof.rb
#
# frozen_string_literal: true
#
# Executable proof for the FOUR "Category A" latent per-process (Ruby heap)
# memory leaks identified in docs/investigation/memory-audit.md.
#
# NOT a tryout (no _try.rb suffix) so the suite never runs it. Run it directly;
# it needs NO Redis server -- every proof is pure Ruby object growth:
#
#   bundle exec ruby try/investigation/process_memory_leak_proof.rb
#
# Companion proof: try/investigation/memory_leak_proof.rb (on branch
# fix/memory-leak) covers the Category C *Redis-side* orphan findings and the
# Category B O(N) materialization high-watermark. This file covers only the
# Ruby-process, permanent-unbounded, append-only registries -- i.e. the only
# category whose growth profile matches the OneTimeSecret symptom (per-process
# RSS climbing over weeks).
#
# The load-bearing point of each proof: the structure is unbounded and has no
# eviction path, BUT Familia itself never drives the trigger. Each leak is armed
# only by a specific *application* call pattern. So each proof demonstrates both
# (1) unbounded growth when the trigger fires, and (2) that the guarded/correct
# usage stays bounded.

require 'base64'
require 'securerandom'

require_relative '../../lib/familia'

# --------------------------------------------------------------------------
$failures = 0
def check(label, ok)
  $failures += 1 unless ok
  puts "  [#{ok ? 'PASS' : 'FAIL'}] #{label}"
  ok
end

def section(title)
  puts "\n#{'=' * 78}\n#{title}\n#{'=' * 78}"
end

puts 'Familia latent per-process (Ruby heap) memory-leak proof'
puts "ruby #{RUBY_VERSION}  familia #{Familia::VERSION}  (no Redis required)"

# ==========================================================================
# PROOF A1 - Encryption request-key cache (TOP OTS suspect)
# ==========================================================================
# Familia::Encryption::Manager#derive_key_without_increment caches the derived
# key in Fiber[:familia_request_cache] when Fiber[:familia_request_cache_enabled]
# is set (manager.rb:146-167). The cache key embeds the PER-RECORD context
# ("Class:field:identifier", encrypted_field_type.rb:184), so cardinality is
# UNBOUNDED in distinct records touched.
#
# Default: caching is OFF (flag nil) -> the Hash is never allocated -> no leak.
# Correct opt-in: with_request_cache wipes on entry AND in an ensure on exit, so
# a pooled fiber starts and ends every request empty (request_cache.rb:36-55).
# The leak: an app that enables the flag at a scope BROADER than one request
# (e.g. sets it once on a long-lived pooled server fiber, or wraps a worker
# loop) never clears the Hash; it grows one retained 32-byte key per distinct
# record, forever.

section 'PROOF A1 - encryption request-key cache: unbounded when mis-scoped, bounded under with_request_cache'

Familia.config.encryption_keys = { v1: Base64.strict_encode64(SecureRandom.bytes(32)) }
Familia.config.current_key_version = :v1
mgr = Familia::Encryption::Manager.new
N = 300

# (1) Mis-scoped: enable the flag the way a pooled fiber that opts in ONCE would,
# without the per-request clear. This is the leak condition.
Fiber[:familia_request_cache_enabled] = true
Fiber[:familia_request_cache] = {}
N.times { |i| mgr.send(:derive_key_without_increment, "Secret:value:secret_#{i}") }
mis_scoped_size = Fiber[:familia_request_cache].size

# (2) Correct opt-in: with_request_cache clears on exit even on exception.
Fiber[:familia_request_cache_enabled] = false
Fiber[:familia_request_cache] = nil
Familia::Encryption.with_request_cache do
  N.times { |i| mgr.send(:derive_key_without_increment, "Secret:value:secret_#{i}") }
end
after_block = Fiber[:familia_request_cache]

# (3) Default: flag never set -> cache never even allocated.
Fiber[:familia_request_cache_enabled] = nil
Fiber[:familia_request_cache] = nil
mgr.send(:derive_key_without_increment, 'Secret:value:default_path')
default_cache = Fiber[:familia_request_cache]

puts "  mis-scoped cache size after #{N} distinct-record derivations: #{mis_scoped_size}"
puts "  cache after with_request_cache block exits:                   #{after_block.inspect}"
puts "  cache on the default (flag-off) path:                         #{default_cache.inspect}"
check("mis-scoped cache grows one entry per distinct record (#{mis_scoped_size} == #{N})", mis_scoped_size == N)
check('with_request_cache wipes the cache on exit (nil)', after_block.nil?)
check('default path never allocates the cache (nil)', default_cache.nil?)
puts '  Interpretation: retained *key material* grows with distinct records over'
puts '  the fiber lifetime iff caching is enabled outside a per-request boundary.'
puts '  OTS relevance: a secrets app deriving per-record keys is the exact shape.'

# ==========================================================================
# PROOF A2 - reconnect! re-registers Redis middleware every call
# ==========================================================================
# register_middleware_once is guarded by @logger_registered/@counter_registered
# so it fires once at boot. reconnect! resets those flags to false and calls it
# again (middleware.rb:91-94), so every reconnect! re-runs RedisClient.register,
# which appends to a process-global middleware list with no dedup and no
# unregister API. Repeated reconnect! (failover, timers, per-error) stacks
# permanent duplicate registrations.

section 'PROOF A2 - reconnect! re-registers middleware (append-only global list)'

reg_count = 0
orig_register = RedisClient.method(:register)
RedisClient.singleton_class.send(:define_method, :register) do |*a, **k, &b|
  reg_count += 1
  orig_register.call(*a, **k, &b)
end
Familia.enable_database_logging = true if Familia.respond_to?(:enable_database_logging=)
Familia.enable_database_counter = true if Familia.respond_to?(:enable_database_counter=)

reg_count = 0
rounds = 5
rounds.times { Familia.reconnect! }
puts "  RedisClient.register invocations across #{rounds} reconnect! calls: #{reg_count}"
check("reconnect! re-registers on every call (#{reg_count} >= #{rounds})", reg_count >= rounds)
puts '  Interpretation: RedisClient has no unregister; each reconnect! leaves one'
puts '  more DatabaseLogger/DatabaseCommandCounter reference on the global list,'
puts '  invoked on every command thereafter. Bounded only if reconnect! is rare.'

# restore
RedisClient.singleton_class.send(:define_method, :register, orig_register)

# ==========================================================================
# PROOF A3 - Instrumentation hook arrays are append-only, no unregister
# ==========================================================================
# on_command/on_pipeline/on_lifecycle/on_error do @hooks[type] << block
# (instrumentation.rb:56-112). There is no off_*/clear API anywhere in lib/.
# Each retained block is a closure that can pin whatever its defining scope
# captured. Familia's own code only ever calls the notify_* side (iterate), so
# the gem never grows @hooks itself -- growth requires repeated app registration
# (per-request, per-connection, or on every code reload).

section 'PROOF A3 - Instrumentation @hooks: append-only, no removal API'

hooks = Familia::Instrumentation.instance_variable_get(:@hooks)
before = hooks[:command].size
2_000.times { Familia::Instrumentation.on_command { |*| } }
after = hooks[:command].size
has_removal = Familia::Instrumentation.respond_to?(:off_command) ||
              Familia::Instrumentation.respond_to?(:clear_hooks) ||
              Familia::Instrumentation.respond_to?(:reset_hooks)
puts "  @hooks[:command] grew #{before} -> #{after} over 2000 registrations"
puts "  removal/unregister API present: #{has_removal}"
check('every on_command registration is retained (grew by 2000)', after - before == 2_000)
check('no unregister/clear API exists to shed them', !has_removal)
hooks[:command].clear # local cleanup so this proof does not perturb others

# ==========================================================================
# PROOF A4 - Familia.members pins every Horreum subclass forever (strong ref)
# ==========================================================================
# Horreum.inherited does `Familia.members << member` (horreum.rb:173) with a
# STRONG reference; the only removers (unload_member/clear_anonymous_members,
# familia.rb:116-130) are documented test-cleanup helpers, never called in
# production. Bounded for a static model set defined once at boot; a permanent
# unbounded leak iff the app mints Horreum subclasses at runtime (per request /
# per tenant / Class.new in a hot path). The subclass, its generated singleton
# methods, and everything it references can never be GC'd.

section 'PROOF A4 - Familia.members: append-only strong-ref registry of subclasses'

before_m = Familia.members.size
50.times { Class.new(Familia::Horreum) { identifier_field :id; field :id } }
after_create = Familia.members.size
GC.start(full_mark: true, immediate_sweep: true)
after_gc = Familia.members.size
puts "  Familia.members: #{before_m} -> #{after_create} (after 50 anon subclasses) -> #{after_gc} (after full GC)"
check('each runtime subclass is appended to the registry (+50)', after_create - before_m == 50)
check('strong reference survives a full GC (not reclaimed)', after_gc == after_create)

# Demonstrate the ONLY escape hatch is the manual test-cleanup helper.
if Familia.respond_to?(:clear_anonymous_members)
  Familia.clear_anonymous_members
  after_manual = Familia.members.size
  puts "  after manual Familia.clear_anonymous_members: #{after_manual}"
  check('only a manual/test helper (clear_anonymous_members) evicts them', after_manual < after_create)
end
puts '  Interpretation: in-gem this is bounded (models defined once at boot). It'
puts '  becomes the classic ORM registry leak only under runtime subclassing --'
puts '  something to confirm against the consuming app, not a default-config leak.'

# --------------------------------------------------------------------------
section 'SUMMARY'
puts 'All four are ruby-process + permanent-unbounded, but each is armed only by a'
puts 'specific application call pattern; Familia never drives the trigger itself.'
puts 'See docs/investigation/memory-audit.md for classification, remediation, and'
puts 'the OTS-side checks that determine which (if any) is the active cause.'
puts($failures.zero? ? "\nALL CHECKS PASSED" : "\n#{$failures} CHECK(S) FAILED")
exit($failures.zero? ? 0 : 1)
