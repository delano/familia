require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Dedicated test class to avoid polluting shared test state
class LoadMissingTestUser < Familia::Horreum
  identifier_field :userid
  field :userid
  field :name
  field :email
end

# Clean slate
LoadMissingTestUser.instances.clear
LoadMissingTestUser.all.each(&:destroy!)

## find_by_id with nonexistent identifier returns nil
LoadMissingTestUser.find_by_id('totally_nonexistent_user_12345')
#=> nil

## load with nonexistent identifier returns nil
LoadMissingTestUser.load('another_nonexistent_user_67890')
#=> nil

## find with nonexistent identifier returns nil
LoadMissingTestUser.find('nope_not_here')
#=> nil

## find_by_dbkey with nonexistent full key returns nil
@fake_key = LoadMissingTestUser.dbkey('nonexistent_key_abc', LoadMissingTestUser.suffix)
LoadMissingTestUser.find_by_dbkey(@fake_key)
#=> nil

## find_by_id with empty string returns nil
LoadMissingTestUser.find_by_id('')
#=> nil

## find_by_id with nil returns nil
LoadMissingTestUser.find_by_id(nil)
#=> nil

## find_by_dbkey with empty key raises ArgumentError
begin
  LoadMissingTestUser.find_by_dbkey('')
  false
rescue ArgumentError
  true
end
#=> true

## find_by_id with check_exists false on missing key returns nil
LoadMissingTestUser.find_by_id('missing_optimized_path', check_exists: false)
#=> nil

## find_by_dbkey with check_exists false on missing key returns nil
@fake_key2 = LoadMissingTestUser.dbkey('missing_optimized_dbkey', LoadMissingTestUser.suffix)
LoadMissingTestUser.find_by_dbkey(@fake_key2, check_exists: false)
#=> nil

## return value for missing key is exactly nil, not a shell object
@result = LoadMissingTestUser.find_by_id('definitely_not_here')
@result.nil?
#=> true

## return value class is NilClass, not LoadMissingTestUser
@result2 = LoadMissingTestUser.load('also_not_here')
@result2.class
#=> NilClass

## saved object is findable, then missing after destroy
@user = LoadMissingTestUser.create!(userid: 'testuser1', name: 'Test', email: 'test@example.com')
@found = LoadMissingTestUser.find_by_id('testuser1')
@found.nil?
#=> false

## found object has correct identifier
@found.userid
#=> 'testuser1'

## after destroy, find_by_id returns nil
@user.destroy!
LoadMissingTestUser.find_by_id('testuser1')
#=> nil

## after destroy, load also returns nil
LoadMissingTestUser.load('testuser1')
#=> nil

## direct redis delete causes find_by_id to return nil (check_exists true)
@user2 = LoadMissingTestUser.create!(userid: 'testuser2', name: 'Test2', email: 'test2@example.com')
LoadMissingTestUser.dbclient.del(@user2.dbkey)
LoadMissingTestUser.find_by_id('testuser2')
#=> nil

## direct redis delete causes find_by_id to return nil (check_exists false)
@user3 = LoadMissingTestUser.create!(userid: 'testuser3', name: 'Test3', email: 'test3@example.com')
LoadMissingTestUser.dbclient.del(@user3.dbkey)
LoadMissingTestUser.find_by_id('testuser3', check_exists: false)
#=> nil

## find_by_id is read-only: stale instance entry persists after find miss
@user4 = LoadMissingTestUser.create!(userid: 'testuser4', name: 'Test4', email: 'test4@example.com')
@had_entry = LoadMissingTestUser.instances.member?('testuser4')
LoadMissingTestUser.dbclient.del(@user4.dbkey)
LoadMissingTestUser.find_by_id('testuser4')
@still_has_entry = LoadMissingTestUser.instances.member?('testuser4')
[@had_entry, @still_has_entry]
#=> [true, true]

# Cleanup
LoadMissingTestUser.instances.clear
LoadMissingTestUser.all.each(&:destroy!)
