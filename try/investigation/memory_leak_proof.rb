# try/investigation/memory_leak_proof.rb
#
# frozen_string_literal: true
#
# Standalone proof for the four memory findings in memory-audit-findings.md.
# NOT a tryout (no _try.rb suffix) - run it directly:
#
#   FAMILIA_TEST_URI=redis://127.0.0.1:6379 ruby try/investigation/memory_leak_proof.rb
#
# Tunables (generous defaults sized for a 32GB box):
#   PROOF_BATCH   objects created+expired per round in Proof A   (default 20_000)
#   PROOF_ROUNDS  number of expiry rounds in Proof A             (default 5)
#   PROOF_GHOSTS  ghost ids seeded into the instances ZSET in B  (default 3_000_000)
#   PROOF_TTL     default_expiration seconds for Proof A model   (default 2)
#
# Each proof prints measured numbers and a PASS/FAIL line. Exit code is non-zero
# if any assertion fails.

require 'delegate'
require 'connection_pool'
require 'redis'

require_relative '../../lib/familia'

Familia.uri = ENV.fetch('FAMILIA_TEST_URI', 'redis://127.0.0.1:6379')

BATCH  = Integer(ENV.fetch('PROOF_BATCH',  '20000'))
ROUNDS = Integer(ENV.fetch('PROOF_ROUNDS', '5'))
GHOSTS = Integer(ENV.fetch('PROOF_GHOSTS', '3000000'))
TTL    = Integer(ENV.fetch('PROOF_TTL',    '2'))

# --------------------------------------------------------------------------
# Measurement helpers
# --------------------------------------------------------------------------

def rss_kb
  if File.exist?('/proc/self/status')
    File.read('/proc/self/status')[/VmRSS:\s+(\d+)/, 1].to_i
  else
    `ps -o rss= -p #{Process.pid}`.to_i
  end
end

def used_memory
  Familia.dbclient.info('memory').fetch('used_memory').to_i
rescue StandardError
  Familia.dbclient.call('INFO', 'memory')[/used_memory:(\d+)/, 1].to_i
end

def connected_clients
  Familia.dbclient.info('clients').fetch('connected_clients').to_i
rescue StandardError
  -1
end

def mb(kb) = (kb / 1024.0).round(1)
def mbb(bytes) = (bytes / 1024.0 / 1024.0).round(1)

$failures = 0
def check(label, ok)
  status = ok ? 'PASS' : 'FAIL'
  $failures += 1 unless ok
  puts "  [#{status}] #{label}"
  ok
end

def section(title)
  puts "\n#{'=' * 78}\n#{title}\n#{'=' * 78}"
end

# Sample peak RSS across a block. Best-effort (GVL-limited), used only as
# corroboration; the primary RSS evidence in Proof B is deterministic.
def with_peak_rss
  peak = rss_kb
  stop = false
  sampler = Thread.new do
    until stop
      cur = rss_kb
      peak = cur if cur > peak
      sleep 0.01
    end
  end
  result = yield
  stop = true
  sampler.join
  [peak, result]
end

# --------------------------------------------------------------------------
# Models
# --------------------------------------------------------------------------

# Expiring model with a class-level unique index. Mirrors a session/token model.
class ProofSession < Familia::Horreum
  feature :expiration
  feature :relationships

  default_expiration TTL

  identifier_field :sessid
  field :sessid
  field :email

  unique_index :email, :email_lookup
end

# Non-expiring model used only to seed a ghost-laden instances ZSET for the
# RSS contrast in Proof B.
class GhostModel < Familia::Horreum
  feature :relationships

  identifier_field :gid
  field :gid
  field :email

  unique_index :email, :email_lookup
end

RebuildStrategies = Familia::Features::Relationships::Indexing::RebuildStrategies
AtomicOps = Familia::AtomicOperations

# --------------------------------------------------------------------------
puts "Familia memory-leak proof"
puts "uri=#{Familia.uri}  BATCH=#{BATCH} ROUNDS=#{ROUNDS} GHOSTS=#{GHOSTS} TTL=#{TTL}s"
begin
  Familia.dbclient.ping
rescue StandardError => e
  abort "Cannot reach Redis at #{Familia.uri}: #{e.class}: #{e.message}"
end

# ==========================================================================
# PROOF A - Finding 1: instances ZSET + unique_index HASH orphan on TTL expiry
# ==========================================================================
# Each round: create BATCH objects with a short TTL, confirm the TTL was set,
# wait for Redis to expire the main hashes, then confirm the main hashes are
# gone while the instances ZSET and the email_lookup HASH retain every entry.
# Primary evidence is cardinality (ZCARD / HLEN); used_memory corroborates.

section 'PROOF A - orphaned instances/index entries under continuous writes (Finding 1)'

# Mechanism (verified): the instances ZSET and the unique_index HASH inherit the
# model default_expiration as a WHOLE-KEY ttl, and that ttl is refreshed on every
# save (touch_instances! / auto_update_class_indexes). So normal app traffic keeps
# the collection keys alive indefinitely, while members belonging to objects whose
# own hash already expired are never pruned (no per-member/per-field ttl, and TTL
# expiry never calls destroy!). The orphans accumulate without bound.
#
# Each round: create BATCH objects, then run keepalive saves (simulating traffic)
# for longer than TTL so the batch's main hashes expire while the collection keys
# stay alive. Then show the batch members are gone-as-objects but still present as
# ZSET members / HASH fields, and that ZCARD grows every round.

inst_key  = ProofSession.instances.dbkey
index_key = ProofSession.email_lookup.dbkey
Familia.dbclient.del(inst_key, index_key)

baseline_used = used_memory
puts "  model default_expiration=#{TTL}s (whole-key ttl, refreshed on every save)"
puts "  baseline used_memory: #{mbb(baseline_used)} MB"
printf "  %-7s %12s %12s %12s %10s %12s\n",
       'round', 'live(s25)', 'orphan(s25)', 'ZCARD', 'ttl(inst)', 'used_MB'

ttl_seen = false
zcards = []
ka = 0
last_live = nil
last_orphan = nil
last_n = nil

ROUNDS.times do |r|
  sample = []
  BATCH.times do |i|
    o = ProofSession.new(sessid: "s-#{r}-#{i}-#{Process.pid}",
                         email: "u-#{r}-#{i}-#{Process.pid}@proof.test")
    o.save
    sample << o if i < 25
  end
  ttl_seen ||= sample.first&.ttl&.positive?

  # Keepalive traffic: refresh the collection whole-key ttl while the batch ages
  # past its own TTL. This is exactly what a live, continuously-writing app does.
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TTL + 2
  while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    ProofSession.new(sessid: "ka-#{ka}-#{Process.pid}",
                     email: "ka-#{ka}-#{Process.pid}@proof.test").save
    ka += 1
    sleep 0.1
  end

  last_live   = sample.count { |o| Familia.dbclient.exists?(o.dbkey) }
  last_orphan = sample.count { |o| !Familia.dbclient.zscore(inst_key, o.identifier).nil? }
  last_n      = sample.size
  zc = Familia.dbclient.zcard(inst_key)
  zcards << zc
  printf "  %-7d %12d %12d %12d %10d %12s\n",
         r + 1, last_live, last_orphan, zc, Familia.dbclient.ttl(inst_key), mbb(used_memory)
end

final_zc   = Familia.dbclient.zcard(inst_key)
final_hl   = Familia.dbclient.hlen(index_key)
final_used = used_memory

puts
check("save() set a TTL on the main hash (precondition)", ttl_seen)
check("collection key stayed ALIVE under continuous writes (ttl>0)",
      Familia.dbclient.ttl(inst_key) > 0)
check("final-round sampled main hashes expired (live=#{last_live}/#{last_n})",
      last_live.zero?)
check("those expired objects still present in instances ZSET (orphans=#{last_orphan}/#{last_n})",
      last_orphan == last_n)
check("index HASH also retained orphans (HLEN=#{final_hl})", final_hl.positive?)
check("ZCARD grew every round - monotonic, unbounded (#{zcards.inspect})",
      zcards.each_cons(2).all? { |a, b| b > a })
puts "  corroborating: used_memory #{mbb(baseline_used)} -> #{mbb(final_used)} MB"
puts "  Interpretation: the collection keys never expire while traffic flows, yet"
puts "  every expired object leaves its ZSET member + HASH field behind. ZCARD/HLEN"
puts "  climb monotonically. destroy! prunes them; TTL expiry never calls destroy!."

# ==========================================================================
# PROOF B - Finding 2: rebuild materializes the whole collection (Ruby RSS)
# ==========================================================================
# Seed GHOSTS ids into GhostModel.instances directly (raw ZADD, no objects).
# rebuild_via_instances calls `instances.members` (the exact line 108) which
# pulls the ENTIRE ZSET into one Ruby array. rebuild_via_scan streams instead.

section 'PROOF B - full materialization vs streaming on rebuild (Finding 2)'

ghost_inst = GhostModel.instances.dbkey
Familia.dbclient.del(ghost_inst, GhostModel.email_lookup.dbkey)

print "  seeding #{GHOSTS} ghost ids into #{ghost_inst} ..."
seeded = 0
(0...GHOSTS).each_slice(50_000) do |slice|
  pairs = slice.flat_map { |i| [i.to_f, "ghost_#{i}"] }
  Familia.dbclient.zadd(ghost_inst, pairs)
  seeded += slice.size
end
puts " done (ZCARD=#{Familia.dbclient.zcard(ghost_inst)})"

# B1 (deterministic, primary): hold the materialized array, measure RSS delta.
GC.start
b0 = rss_kb
members = GhostModel.instances.members        # <-- rebuild_strategies.rb:108
b1 = rss_kb
materialize_delta = b1 - b0
puts "  members.length=#{members.length}  RSS delta from .members: #{mb(materialize_delta)} MB"
members = nil
GC.start

# B2 (contrast): stream the same ZSET, measure RSS delta (should be ~flat).
s0 = rss_kb
streamed = 0
Familia.dbclient.zscan_each(ghost_inst) { |_m, _s| streamed += 1 }
s1 = rss_kb
stream_delta = s1 - s0
puts "  zscan_each streamed=#{streamed}  RSS delta from streaming: #{mb(stream_delta)} MB"

# B3 (corroboration): run the real strategy methods, sample peak RSS of each.
GC.start
idx = GhostModel.email_lookup
peak_scan = nil
begin
  base = rss_kb
  peak_scan, = with_peak_rss do
    RebuildStrategies.rebuild_via_scan(
      GhostModel, :email, :add_to_class_email_lookup, idx, batch_size: 1000
    )
  end
  puts "  rebuild_via_scan      peak RSS delta: #{mb(peak_scan - base)} MB"
rescue StandardError => e
  puts "  rebuild_via_scan skipped: #{e.class}: #{e.message}"
end

GC.start
base = rss_kb
peak_inst, = with_peak_rss do
  RebuildStrategies.rebuild_via_instances(
    GhostModel, :email, :add_to_class_email_lookup, idx, batch_size: 1000
  )
end
puts "  rebuild_via_instances peak RSS delta: #{mb(peak_inst - base)} MB"

puts
check("`.members` materialization RSS scales with N (#{mb(materialize_delta)} MB for #{GHOSTS} ids)",
      materialize_delta > GHOSTS / 200) # KB; ~>5 bytes resident/id, trivially true if it materializes
check("streaming the same ZSET cost materially less than materializing " \
      "(stream #{mb(stream_delta)} MB << members #{mb(materialize_delta)} MB)",
      stream_delta < materialize_delta)
puts "  Interpretation: via_instances loads the whole (ghost-bloated) ZSET into"
puts "  Ruby before batching; via_scan streams. O(N) high-watermark over the"
puts "  unbounded base from Finding 1."

# ==========================================================================
# PROOF C - Finding 3: failed rebuild leaves an orphaned temp key (no TTL)
# ==========================================================================
# Exercise the real atomic_swap rescue branch (atomic_operations.rb:80-83):
# HSET into the temp key so the `exists > 0` guard passes, then force RENAME to
# raise a non-"no such key" error. The temp key is preserved with no TTL.

section 'PROOF C - orphaned rebuild temp key with no TTL (Finding 3)'

class FailingRename < SimpleDelegator
  def rename(*)
    raise Redis::CommandError, 'OOM command not allowed (simulated)'
  end
end

final_key = "proof:tempkeyleak:final"
temp_key  = AtomicOps.build_temp_key(final_key)
Familia.dbclient.del(final_key, temp_key)

# Populate the temp key the way a rebuild would (full index copy lives here).
Familia.dbclient.hset(temp_key, 'a@x', '1', 'b@x', '2', 'c@x', '3')

raised = false
begin
  AtomicOps.atomic_swap(temp_key, final_key, FailingRename.new(Familia.dbclient))
rescue Redis::CommandError
  raised = true
end

temp_ttl    = Familia.dbclient.ttl(temp_key)
temp_exists = Familia.dbclient.exists?(temp_key)

# Timestamp-collision footnote: same-second rebuilds reuse the same temp key.
collide = AtomicOps.build_temp_key(final_key) == AtomicOps.build_temp_key(final_key)

puts "  after forced swap failure: exists=#{temp_exists} ttl=#{temp_ttl}"
check("atomic_swap re-raised (preserve-and-raise branch taken)", raised)
check("temp key was preserved (leaked), not cleaned up", temp_exists)
check("temp key has NO expiration (ttl == -1)", temp_ttl == -1)
check("build_temp_key collides within the same second", collide)
Familia.dbclient.del(final_key, temp_key)
puts "  Interpretation: every failed/interrupted rebuild orphans a full"
puts "  index-sized HASH with no TTL. Unbounded across failures."

# ==========================================================================
# PROOF D - Finding 4: README connection_provider recreates the pool per call
# ==========================================================================
# Not a permanent leak (pools are GC-reclaimable) - it is connection churn /
# fd pressure and defeated pooling. Proven by object identity.

section 'PROOF D - connection_provider per-call pool allocation (Finding 4)'

uri = Familia.uri.to_s
N = 25

# README.md:380-384 - new ConnectionPool on every call.
readme_provider = lambda do |u|
  ConnectionPool.new(size: 10, timeout: 5) { Redis.new(url: u) }
end

# docs/guides/index.md:94 - memoized per-uri.
memo_pools = {}
memoized_provider = lambda do |u|
  memo_pools[u] ||= ConnectionPool.new(size: 10, timeout: 5) { Redis.new(url: u) }
end

before_clients = connected_clients
readme_ids = []
N.times do
  pool = readme_provider.call(uri)
  pool.with { |c| c.ping } # force an actual socket open
  readme_ids << pool.object_id
end
after_readme_clients = connected_clients

memo_ids = Array.new(N) { memoized_provider.call(uri).object_id }

puts "  README provider:   #{readme_ids.uniq.size} distinct pool objects over #{N} calls"
puts "  memoized provider: #{memo_ids.uniq.size} distinct pool object over #{N} calls"
puts "  connected_clients: #{before_clients} -> #{after_readme_clients} (after #{N} README checkouts)"

check("README provider allocates a NEW pool every call (#{readme_ids.uniq.size}==#{N})",
      readme_ids.uniq.size == N)
check("memoized provider reuses ONE pool (#{memo_ids.uniq.size}==1)",
      memo_ids.uniq.size == 1)
GC.start
puts "  Note: orphaned README pools are GC-reclaimable, so this is connection"
puts "  churn / fd pressure under throughput, not permanent memory growth."

# --------------------------------------------------------------------------
section 'CLEANUP'
killed = Familia.dbclient.del(
  ProofSession.instances.dbkey, ProofSession.email_lookup.dbkey,
  GhostModel.instances.dbkey, GhostModel.email_lookup.dbkey
)
puts "  deleted #{killed} proof collection keys (ProofSession orphans self-expire)"

# --------------------------------------------------------------------------
section 'SUMMARY'
puts $failures.zero? ? "ALL CHECKS PASSED" : "#{$failures} CHECK(S) FAILED"
exit($failures.zero? ? 0 : 1)
