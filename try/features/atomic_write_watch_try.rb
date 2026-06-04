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

# Clean slate
WatchTestUser.instances.clear
WatchTestUser.all.each(&:destroy!)

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

## watched atomic_write retries on OptimisticLockError (simulated WATCH abort)
@u9 = WatchTestUser.new(email: 'watch9@example.com', name: 'Watch9')
attempt_count = 0
original_transaction = @u9.method(:transaction)
@u9.define_singleton_method(:transaction) do |&blk|
  attempt_count += 1
  if attempt_count == 1
    # Simulate a WATCH abort on first attempt: multi returns nil
    blk.call(nil)
    Familia::MultiResult.new(nil)
  else
    original_transaction.call(&blk)
  end
end
@u9.atomic_write(watch_keys: [@u9.dbkey]) do
  @u9.role = 'retried'
end
[attempt_count >= 2, WatchTestUser.find_by_id('watch9@example.com').role]
#=> [true, 'retried']

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
WatchTestUser.all.each(&:destroy!)
