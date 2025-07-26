require_relative '../helpers/test_helpers'

# Test reserved keyword handling
group "Reserved Keywords Edge Cases"

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier :email
    # These should fail with reserved keywords
    begin
      field :ttl      # Reserved for expiration
      field :db       # Reserved for database
      field :redis    # Reserved for connection
    rescue => e
      # Expected to fail
    end

    # Workarounds
    field :secret_ttl
    field :user_db
    field :redis_config
  end
end

try "cannot use ttl as field name" do
  begin
    Class.new(Familia::Horreum) do
      field :ttl
    end
    false  # Should not reach here
  rescue => e
    true   # Expected error
  end
end

try "workaround with prefixed names works" do
  user = @user_class.new(email: "test@example.com")
  user.secret_ttl = 3600
  user.user_db = 5
  user.redis_config = {host: "localhost"}
  user.save

  user.secret_ttl == 3600 &&
    user.user_db == 5 &&
    user.redis_config.is_a?(Hash)
ensure
  user&.delete!
end

try "reserved methods still work normally" do
  user = @user_class.new(email: "test@example.com")
  user.save

  user.respond_to?(:ttl) &&
    user.respond_to?(:db) &&
    user.respond_to?(:redis)
ensure
  user&.delete!
end
