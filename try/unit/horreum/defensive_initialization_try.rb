# try/horreum/defensive_initialization_try.rb

require_relative '../../support/helpers/test_helpers'

# Test defensive initialization behavior
class User < Familia::Horreum
  field :email
  list :sessions
  zset :metrics

  def initialize(email = nil)
    # This is the common mistake - overriding initialize without calling super
    @email = email
    # Missing: super() or initialize_relatives
  end
end

class SafeUser < Familia::Horreum
  field :email
  list :sessions
  zset :metrics

  def init
    # This is the correct way - using the init hook
    # Fields are already set by initialize, no need to override
  end
end

# Setup instances for testing
@user = User.new("test@example.com")
@safe_user = SafeUser.new
@safe_user.email = "safe@example.com"

## Test that accessing relationships after bad initialize triggers lazy initialization
@user.email
#=> "test@example.com"

## Test that sessions works with lazy initialization
@user.sessions.class
#=> Familia::ListKey

## Test that metrics also works with lazy initialization
@user.metrics.class
#=> Familia::SortedSet

## Test that safe user works normally
@safe_user.email
#=> "safe@example.com"

## Test that safe user sessions work
@safe_user.sessions.class
#=> Familia::ListKey

## Test that relatives_initialized flag prevents double initialization
@user.singleton_class.instance_variable_get(:@relatives_initialized)
#=> true

## Test that manual initialize_relatives call is no-op
@user.initialize_relatives
@user.sessions.class
#=> Familia::ListKey

## Test that the original problem is now fixed - bad override still works
class BadUser < Familia::Horreum
  field :email
  list :sessions

  def initialize(email)
    # Bad: overriding initialize without calling super
    @email = email
    # Missing: super() or initialize_relatives
  end
end

@bad_user = BadUser.new("bad@example.com")
@bad_user.email
#=> "bad@example.com"

## Test that relationships work despite bad initialize (lazy initialization kicks in)
@bad_user.sessions.class
#=> Familia::ListKey

## Test that the bad user can actually use the relationships
@bad_user.sessions.add("session_123")
@bad_user.sessions.size > 0
#=> true
