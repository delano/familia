require_relative '../helpers/test_helpers'

# Comprehensive configuration scenarios
group "Configuration Scenarios"

try "multi-database configuration" do
  # Test database switching
  user_class = Class.new(Familia::Horreum) do
    identifier :email
    field :name
    db 5
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  user.db == 5 && user.exists?
ensure
  user&.delete!
end

try "custom Redis URI configuration" do
  # Test with custom URI
  original_uri = Familia.uri
  test_uri = "redis://localhost:6379/10"

  Familia.uri = test_uri
  current_uri = Familia.uri

  current_uri == test_uri
ensure
  Familia.uri = original_uri
end

try "feature configuration inheritance" do
  base_class = Class.new(Familia::Horreum) do
    identifier :id
    feature :expiration
    ttl 1800
  end

  child_class = Class.new(base_class) do
    ttl 3600  # Override parent TTL
  end

  base_instance = base_class.new(id: "base")
  child_instance = child_class.new(id: "child")

  base_instance.class.ttl == 1800 &&
    child_instance.class.ttl == 3600
end

try "serialization method configuration" do
  custom_class = Class.new(Familia::Horreum) do
    identifier :id
    field :data
    dump_method :to_yaml
    load_method :from_yaml
  end

  instance = custom_class.new(id: "test")

  instance.dump_method == :to_yaml &&
    instance.load_method == :from_yaml
end
