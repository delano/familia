# Performance benchmarks separate from stress tests

require_relative '../helpers/test_helpers'
require 'benchmark'

## serialization performance comparison
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :name
  field :data
end

large_data = { items: (1..1000).to_a, metadata: "x" * 1000 }

json_time = Benchmark.realtime do
  100.times { JSON.dump(large_data) }
end

familia_time = Benchmark.realtime do
  100.times { Familia.distinguisher(large_data) }
end

json_time > 0 && familia_time > 0
#=!> StandardError

## bulk operations vs individual saves
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :name
  field :data
end

users = 100.times.map { |i|
  user_class.new(email: "user#{i}@example.com", name: "User #{i}")
}

individual_time = Benchmark.realtime do
  users.each(&:save)
end

# Cleanup for next test
users.each(&:delete!)

individual_time > 0
#=!> StandardError

## Valkey/Redis type access performance
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :name
  field :data
end

user = user_class.new(email: "perf@example.com")
user.save

access_time = Benchmark.realtime do
  1000.times { user.set(:tags) }
end

result = access_time > 0
user.delete!
result
#=!> StandardError
