# try/support/smoke/installed_gem.rb
#
# frozen_string_literal: true

# Smoke test for an installed familia gem.
#
# The Gem Package workflow (.github/workflows/gem-package.yml) builds the gem
# with `gem build`, installs the .gem file into an empty GEM_HOME and runs
# this script against a Valkey service container. It is not a tryout: the
# file name is outside the *_try.rb / *.try.rb pattern, so `try` never picks
# it up. It loads nothing from this checkout; familia must come from an
# installed gem, and the script fails if it does not.
#
# Usage:
#
#   FAMILIA_SMOKE_URI=redis://127.0.0.1:6379/0 ruby try/support/smoke/installed_gem.rb
#
# Optional:
#
#   FAMILIA_SMOKE_EXPECT_VERSION   fail unless Familia::VERSION equals this
#   FAMILIA_SMOKE_EXPECT_BUNDLER   "true" or "false": fail unless Bundler is
#                                  (or is not) loaded
#
# Every key the script writes is under a random prefix. It fails if any key
# under that prefix survives destroy!, deletes leftovers on the way out, and
# never flushes, so it is safe to run against a shared server.

# Keep the ok / not ok lines in order with abort's message on stderr.
$stdout.sync = true

load_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
require 'familia'
load_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - load_started) * 1000).round

require 'securerandom'

def check(description)
  abort "not ok - #{description}" unless yield
  puts "ok - #{description}"
end

def check_equal(description, actual, expected)
  abort "not ok - #{description}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
  puts "ok - #{description}"
end

uri = ENV.fetch('FAMILIA_SMOKE_URI', '')
abort 'FAMILIA_SMOKE_URI is not set (for example redis://127.0.0.1:6379/0)' if uri.empty?

# --- The installed gem ------------------------------------------------------

puts "# require 'familia' took #{load_ms}ms"
spec = Gem.loaded_specs['familia']
check('familia was activated as a gem') { spec }

spec_dirs = Gem.path.map { |dir| File.join(dir, 'specifications') }
check("its gemspec is an installed one (#{spec.loaded_from})") do
  spec_dirs.include?(File.dirname(spec.loaded_from.to_s))
end

entry_point = File.join(spec.full_gem_path, 'lib', 'familia.rb')
check("lib/familia.rb was loaded from #{spec.full_gem_path}") { $LOADED_FEATURES.include?(entry_point) }

check_equal('Familia::VERSION matches the installed gemspec', Familia::VERSION, spec.version.to_s)
expected_version = ENV.fetch('FAMILIA_SMOKE_EXPECT_VERSION', '')
unless expected_version.empty?
  check_equal('Familia::VERSION matches FAMILIA_SMOKE_EXPECT_VERSION', Familia::VERSION, expected_version)
end

case ENV.fetch('FAMILIA_SMOKE_EXPECT_BUNDLER', '')
when 'true' then check('Bundler is loaded') { defined?(Bundler) }
when 'false' then check('Bundler is not loaded') { !defined?(Bundler) }
end

# --- Against the server -----------------------------------------------------

Familia.uri = uri
check_equal('the server answers PING', Familia.dbclient.ping, 'PONG')

SMOKE_PREFIX = "familia_smoke_#{SecureRandom.hex(6)}".freeze

# String, Integer and Boolean fields, one of each collection type, and a
# unique index from the relationships feature.
class SmokeUser < Familia::Horreum
  prefix SMOKE_PREFIX
  feature :relationships

  identifier_field :userid
  field :userid
  field :email
  field :name
  field :visits
  field :active

  list :sessions
  set :tags
  zset :scores
  hashkey :settings

  unique_index :email, :email_index
end

def smoke_keys
  Familia.dbclient.scan_each(match: "#{SMOKE_PREFIX}:*").to_a
end

begin
  user = SmokeUser.new(
    userid: SecureRandom.uuid,
    email: "#{SMOKE_PREFIX}@example.com",
    name: 'Smoke',
    visits: 3,
    active: false,
  )

  # Horreum: save and load
  check_equal('save', user.save, true)
  check('exists? after save') { SmokeUser.exists?(user.userid) }
  loaded = SmokeUser.load(user.userid)
  check_equal(
    'load round-trips String, Integer and false fields',
    [loaded&.email, loaded&.name, loaded&.visits, loaded&.active],
    [user.email, 'Smoke', 3, false],
  )
  check_equal('find_by_email via unique_index', SmokeUser.find_by_email(user.email)&.userid, user.userid)

  # Collections
  user.sessions.push('s1', 's2')
  user.sessions << 's3'
  check_equal('list push and members', user.sessions.members, %w[s1 s2 s3])

  user.tags.add('admin', 'beta')
  check_equal('set add and members', user.tags.members.sort, %w[admin beta])
  check('set member?') { user.tags.member?('admin') && !user.tags.member?('nobody') }

  user.scores.add('bravo', 2.5)
  user.scores.add('alpha', 1)
  check_equal('sorted set members in score order', user.scores.members, %w[alpha bravo])
  check_equal('sorted set score', user.scores.score('bravo'), 2.5)

  user.settings['theme'] = 'dark'
  user.settings.update('lang' => 'en')
  check_equal('hash key get', user.settings['theme'], 'dark')
  check_equal('hash key keys', user.settings.keys.sort, %w[lang theme])

  # One MULTI/EXEC for a scalar field and two collections
  committed = user.atomic_write do
    user.name = 'Smoke Atomic'
    user.tags.add('atomic')
    user.sessions.push('s4')
  end
  check_equal('atomic_write', committed, true)
  reloaded = SmokeUser.load(user.userid)
  check_equal(
    'atomic_write committed the field and both collections',
    [reloaded&.name, reloaded&.tags&.member?('atomic'), reloaded&.sessions&.size],
    ['Smoke Atomic', true, 4],
  )

  # Destroy removes the hash, every collection and the index entry
  user.destroy!
  check('exists? is false after destroy!') { !SmokeUser.exists?(user.userid) }
  check('load returns nil after destroy!') { SmokeUser.load(user.userid).nil? }
  check('find_by_email returns nil after destroy!') { SmokeUser.find_by_email(user.email).nil? }
  check_equal("no keys left under #{SMOKE_PREFIX}:", smoke_keys, [])
ensure
  begin
    leftovers = smoke_keys
    Familia.dbclient.del(*leftovers) unless leftovers.empty?
  rescue StandardError => e
    warn "# cleanup under #{SMOKE_PREFIX}: skipped (#{e.class}: #{e.message})"
  end
end

puts "# all checks passed with familia #{Familia::VERSION} on Ruby #{RUBY_VERSION}"
