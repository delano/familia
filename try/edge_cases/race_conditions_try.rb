# try/edge_cases/race_conditions_try.rb
#
# frozen_string_literal: true

# Test connection race conditions

require_relative '../support/helpers/test_helpers'

## concurrent connection access test
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :counter
end

user = user_class.new(email: 'test@example.com', counter: 0)
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
user.delete!

# Count successful operations
successes = results.count { |r| r == 'success' }
successes > 0 # Should have some successes
#=!> StandardError

## connection pool stress test
## We're just checking whether it completes within a reasonable time frame.
## If it does fail either bc of the duration or contention then it's a problem.
success_count = 0
threads = []
mutex = Mutex.new

# Test concurrent connections
100.times do |i|
  threads << Thread.new do
    # Try to get a connection and perform an operation
    dbclient = Familia.dbclient
    dbclient.ping
    success_count += 1
  end
end

threads.each(&:join)

# Should have some successful connections
success_count > 0
#=%> 220
