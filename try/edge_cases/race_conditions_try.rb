require_relative '../helpers/test_helpers'

# Test connection race conditions
group 'Race Conditions Edge Cases'

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :counter
  end
end

try 'concurrent connection access causes race condition' do
  user = @user_class.new(email: 'test@example.com', counter: 0)
  user.save

  threads = []
  results = []

  # Simulate high concurrency
  10.times do
    threads << Thread.new do
      user.incr(:counter)
      results << 'success'
    rescue StandardError => e
      results << "error: #{e.class.name}"
    end
  end

  threads.each(&:join)

  # May show race condition issues
  errors = results.count { |r| r.start_with?('error') }
  errors > 0 # Expects some race condition errors
ensure
  user&.delete!
end

try 'connection pool stress test' do
  users = []

  # Create multiple users concurrently
  threads = []
  20.times do |i|
    threads << Thread.new do
      user = @user_class.new(email: "user#{i}@example.com")
      user.save
      users << user
    end
  end

  threads.each(&:join)

  # Check for connection issues
  users.length > 0 # Some should succeed despite race conditions
ensure
  begin
    users.each(&:delete!)
  rescue StandardError
    nil
  end
end
