require_relative '../helpers/test_helpers'

# Test Horreum Redis commands
group "Horreum Commands"

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier :email
    field :name
    field :score
  end
  @user = @user_class.new(email: "test@example.com", name: "Test")
  @user.save
end

try "hget/hset operations" do
  @user.hset("name", "Updated")
  @user.hget("name") == "Updated"
end

try "increment/decrement operations" do
  @user.hset("score", "100")
  @user.incr("score", 10)
  @user.hget("score").to_i == 110 &&
    @user.decr("score", 5) == 105
end

try "field existence and removal" do
  @user.hset("temp_field", "value")
  exists_before = @user.key?("temp_field")
  @user.remove_field("temp_field")
  exists_after = @user.key?("temp_field")

  exists_before && !exists_after
end

try "bulk field operations" do
  fields = @user.hkeys
  values = @user.hvals
  all_data = @user.hgetall

  fields.is_a?(Array) &&
    values.is_a?(Array) &&
    all_data.is_a?(Hash)
end

cleanup do
  @user&.delete!
end
