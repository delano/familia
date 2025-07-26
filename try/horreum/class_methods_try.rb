require_relative '../helpers/test_helpers'

# Test Horreum class methods
group "Horreum Class Methods"

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :name
    field :age
  end
end

try "create factory method with existence checking" do
  user = @user_class.create(email: "test@example.com", name: "Test")
  exists = @user_class.exists?("test@example.com")

  user.is_a?(@user_class) && exists
ensure
  @user_class.destroy!("test@example.com")
end

try "multiget retrieves multiple objects" do
  @user_class.create(email: "user1@example.com", name: "User1")
  @user_class.create(email: "user2@example.com", name: "User2")

  users = @user_class.multiget("user1@example.com", "user2@example.com")

  users.length == 2 && users.all? { |u| u.is_a?(@user_class) }
ensure
  @user_class.destroy!("user1@example.com", "user2@example.com")
end

try "find_keys returns matching Redis keys" do
  @user_class.create(email: "test@example.com", name: "Test")
  keys = @user_class.find_keys

  keys.any? { |key| key.include?("test@example.com") }
ensure
  @user_class.destroy!("test@example.com")
end
