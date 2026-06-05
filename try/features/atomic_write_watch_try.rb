# try/features/atomic_write_watch_try.rb
#
# Tests for WATCH composition into atomic_write (issue #288).
# Verifies that atomic_write(watch_keys:, pre_check:) provides
# race-safe optimistic locking for create-only patterns like build.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class WatchTestUser < Familia::Horreum
  identifier_field :email
  field :email
  field :name
  field :role
  set :tags
  list :sessions
end

# Clean slate. Use a raw DEL sweep rather than WatchTestUser.all.each(&:destroy!)
# because the real-race tests below intentionally create PARTIAL keys from a
# second connection (a key with no identifier/email field). destroy! would
# raise Familia::NoIdentifier on such a key, so flush keys directly instead.
def flush_watch_test_keys!
  raw = Redis.new(url: Familia.uri.to_s)
  %w[watch_test_user:* watch_exhaust:*].each do |pattern|
    keys = raw.keys(pattern)
    raw.del(*keys) unless keys.empty?
  end
ensure
  raw&.close
end

WatchTestUser.instances.clear
flush_watch_test_keys!

## atomic_write with watch_keys persists scalars and collections
@u1 = WatchTestUser.new(email: 'watch1@example.com', name: 'Watch1')
@u1.atomic_write(watch_keys: [@u1.dbkey]) do
  @u1.role = 'admin'
  @u1.tags.add('staff')
  @u1.sessions.push('sess1')
end
@r1 = WatchTestUser.find_by_id('watch1@example.com')
[@r1.name, @r1.role, @r1.tags.members, @r1.sessions.members]
#=> ['Watch1', 'admin', ['staff'], ['sess1']]

## atomic_write with watch_keys and pre_check executes pre_check
@u2 = WatchTestUser.new(email: 'watch2@example.com', name: 'Watch2')
@u2.save
@u3 = WatchTestUser.new(email: 'watch2@example.com', name: 'Watch2-dup')
@pre_check_raised = false
begin
  @u3.atomic_write(
    watch_keys: [@u3.dbkey],
    pre_check: -> { raise Familia::RecordExistsError, @u3.dbkey if @u3.exists? }
  ) { @u3.tags.add('should_not_persist') }
rescue Familia::RecordExistsError
  @pre_check_raised = true
end
@pre_check_raised
#=> true

## pre_check without watch_keys raises ArgumentError
@u4 = WatchTestUser.new(email: 'watch4@example.com', name: 'Watch4')
begin
  @u4.atomic_write(pre_check: -> { true }) { @u4.name = 'x' }
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## pre_check with empty watch_keys array also raises ArgumentError
@u4b = WatchTestUser.new(email: 'watch4b@example.com', name: 'Watch4b')
begin
  @u4b.atomic_write(watch_keys: [], pre_check: -> { true }) { @u4b.name = 'x' }
  :no_raise
rescue ArgumentError
  :raised
end
#=> :raised

## atomic_write with empty watch_keys array falls back to unwatched path
@u5 = WatchTestUser.new(email: 'watch5@example.com', name: 'Watch5')
@u5.atomic_write(watch_keys: []) do
  @u5.role = 'viewer'
  @u5.tags.add('unwatched')
end
@r5 = WatchTestUser.find_by_id('watch5@example.com')
[@r5.name, @r5.role, @r5.tags.members]
#=> ['Watch5', 'viewer', ['unwatched']]

## watched atomic_write clears dirty state on success
@u6 = WatchTestUser.new(email: 'watch6@example.com', name: 'Watch6')
@u6.atomic_write(watch_keys: [@u6.dbkey]) do
  @u6.role = 'editor'
end
@u6.dirty?
#=> false

## watched atomic_write updates instances timeline
@u7 = WatchTestUser.new(email: 'watch7@example.com', name: 'Watch7')
@u7.atomic_write(watch_keys: [@u7.dbkey]) { @u7.role = 'member' }
WatchTestUser.in_instances?('watch7@example.com')
#=> true

## watched atomic_write rolls back on exception in user block
@u8 = WatchTestUser.new(email: 'watch8@example.com', name: 'Watch8')
@u8.save
@u8.tags.add('keep_me')
begin
  @u8.atomic_write(watch_keys: [@u8.dbkey]) do
    @u8.name = 'Should not persist'
    @u8.tags.add('should_not_persist')
    raise 'boom'
  end
rescue RuntimeError
  # expected
end
@r8 = WatchTestUser.find_by_id('watch8@example.com')
[@r8.name, @r8.tags.members.sort]
#=> ['Watch8', ['keep_me']]

## watched atomic_write retries on REAL WATCH abort, then succeeds
# A pre_check that, from a SECOND independent connection, mutates the
# watched key on the FIRST attempt only. That out-of-band write happens
# inside the WATCH window, so attempt 1's EXEC is aborted by Redis; the
# primitive retries, attempt 2 sees no interfering write and commits. The
# atomic_write's own value must be the one that persists.
@racer9 = Redis.new(url: Familia.uri.to_s)
@u9 = WatchTestUser.new(email: 'watch9@example.com', name: 'Watch9')
@attempt_count9 = 0
@u9.atomic_write(
  watch_keys: [@u9.dbkey],
  pre_check: -> {
    @attempt_count9 += 1
    @racer9.hset(@u9.dbkey, 'name', 'RacerTouch') if @attempt_count9 == 1
  }
) do
  @u9.role = 'retried'
end
@r9 = WatchTestUser.find_by_id('watch9@example.com')
[@attempt_count9, @r9.role, @r9.name]
#=> [2, 'retried', 'Watch9']

## watched atomic_write raises OptimisticLockError after exhausting retries
# A pre_check that mutates the watched key from a SECOND connection on
# EVERY attempt, so every EXEC aborts and retries are exhausted. The racer's
# value must survive (no silent overwrite by atomic_write). RED on the old
# split-connection code (WATCH was inert -> EXEC always committed), GREEN
# now that WATCH + MULTI/EXEC share one connection.
@racer10 = Redis.new(url: Familia.uri.to_s)
@racer10.hset('watch_exhaust:key', 'name', 'RacerOwned')
@u_ex = WatchTestUser.new(email: 'watch_exhaust@example.com', name: 'ExhaustVictim')
# WATCH a key the racer keeps changing; persist would target the user's key.
@watched_key = 'watch_exhaust:key'
@counter10 = 0
begin
  @u_ex.atomic_write(
    watch_keys: [@watched_key],
    pre_check: -> {
      @counter10 += 1
      @racer10.hset(@watched_key, 'name', "RacerOwned#{@counter10}")
    }
  ) do
    @u_ex.role = 'should_not_persist'
  end
  :no_raise
rescue Familia::OptimisticLockError
  :raised
end
#=> :raised

## ... and the exhausted-retry race left the racer's value intact (no overwrite)
[@counter10 >= 3, @racer10.hget('watch_exhaust:key', 'name').start_with?('RacerOwned')]
#=> [true, true]

## save_if_not_exists! real race: key created in WATCH window then retry raises RecordExistsError
# Stub the instance exists? to report false (so the in-WATCH existence check
# passes) but, as a side effect, create the key from a SECOND connection.
# attempt 1: exists?->false, side-effect creates key, EXEC aborts (watched
# key changed). retry attempt 2: exists? side-effect runs again but the key
# already exists from attempt 1, and the now-real key makes the WATCH window
# check raise RecordExistsError -- i.e. no silent overwrite of the racer's row.
@u_sine = WatchTestUser.new(email: 'watch_sine@example.com', name: 'SineRace')
# Closure-captured locals: a singleton method defined with a block evaluates
# @ivars against the SINGLETON object (the instance), not this top-level
# binding, so use lexical locals here. @sine_box aliases the same mutable
# array so the next test case can read the attempt count.
sine_box = [0]
sine_racer = Redis.new(url: Familia.uri.to_s)
@sine_box = sine_box
real_exists = WatchTestUser.instance_method(:exists?)
@u_sine.define_singleton_method(:exists?) do
  sine_box[0] += 1
  if sine_box[0] == 1
    # Report absent, but as a side effect create the key out-of-band from a
    # second connection -- inside the WATCH window -- so attempt 1's EXEC is
    # aborted by the changed watched key.
    sine_racer.hset(dbkey, 'name', 'RacerCreated')
    false
  else
    real_exists.bind(self).call # now reflects reality: the key exists
  end
end
begin
  @u_sine.save_if_not_exists!
  :no_raise
rescue Familia::RecordExistsError
  :raised
end
#=> :raised

## save_if_not_exists! real race took >=2 attempts and left racer's value intact
[@sine_box[0] >= 2, Redis.new(url: Familia.uri.to_s).hget(@u_sine.dbkey, 'name')]
#=> [true, 'RacerCreated']

## build with block uses WATCH path (duplicate rejected even under concurrent setup)
@u10 = WatchTestUser.build(email: 'watch10@example.com', name: 'First') do |u|
  u.tags.add('original')
end
@dup_rejected = false
begin
  WatchTestUser.build(email: 'watch10@example.com', name: 'Second') do |u|
    u.tags.add('duplicate')
  end
rescue Familia::RecordExistsError
  @dup_rejected = true
end
@r10 = WatchTestUser.find_by_id('watch10@example.com')
[@dup_rejected, @r10.name, @r10.tags.members]
#=> [true, 'First', ['original']]

## watched atomic_write raises OperationModeError when nested inside transaction
@u11 = WatchTestUser.new(email: 'watch11@example.com', name: 'Watch11')
@u11.save
begin
  Familia.transaction do
    @u11.atomic_write(watch_keys: [@u11.dbkey]) { @u11.name = 'fail' }
  end
  :no_raise
rescue Familia::OperationModeError
  :raised
end
#=> :raised

# Cleanup
WatchTestUser.instances.clear
flush_watch_test_keys!
