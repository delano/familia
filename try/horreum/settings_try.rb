require_relative '../helpers/test_helpers'

# Test Horreum settings
group "Horreum Settings"

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :name
  end
end

try "database selection inheritance" do
  @user_class.db 5
  user = @user_class.new(email: "test@example.com")

  user.db == 5
end

try "custom serialization methods" do
  @user_class.dump_method :to_json
  @user_class.load_method :from_json
  user = @user_class.new(email: "test@example.com")

  user.dump_method == :to_json &&
    user.load_method == :from_json
end

try "redisdetails comprehensive state inspection" do
  user = @user_class.new(email: "test@example.com", name: "Test")
  details = user.redisdetails

  details.is_a?(Hash) &&
    details.key?(:key) &&
    details.key?(:db)
end

try "redisuri generation with suffix" do
  user = @user_class.new(email: "test@example.com")
  uri = user.redisuri("suffix")

  uri.include?("suffix")
end
