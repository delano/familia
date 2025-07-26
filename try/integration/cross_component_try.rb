require_relative '../helpers/test_helpers'

# Test cross-component integration scenarios
group "Cross-Component Integration"

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier :email
    field :name
    feature :expiration
    feature :safe_dump
    ttl 3600
  end
end

try "Horreum with multiple features integration" do
  user = @user_class.new(email: "test@example.com", name: "Integration Test")
  user.save

  # Test expiration feature
  user.expire(1800)
  ttl_works = user.realttl > 0

  # Test safe_dump feature
  safe_data = user.safe_dump
  safe_dump_works = safe_data.is_a?(Hash)

  ttl_works && safe_dump_works
ensure
  user&.delete!
end

try "RedisType relations with Horreum expiration" do
  user = @user_class.new(email: "test@example.com")
  user.save
  user.expire(1800)

  # Create related RedisType
  tags = user.set(:tags)
  tags << "ruby" << "redis"

  # Expiration should cascade
  tags.exists? && user.exists?
ensure
  user&.delete!
end
