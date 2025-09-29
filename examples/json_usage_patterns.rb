# examples/json_usage_patterns.rb
#
# This file demonstrates the JSON serialization patterns available in Familia,
# showing both the secure defaults and optional developer convenience features.

require_relative '../lib/familia'

# Example model setup
class User < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  field :name
  field :email
  encrypted_field :password_hash  # This will be concealed in JSON
  list :tags
  set :permissions
end

# Configure encryption (required for encrypted_fields)
Familia.config.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.current_key_version = :v1

# Create and save a user
user = User.new(
  user_id: 'user123',
  name: 'Alice Johnson',
  email: 'alice@example.com',
  password_hash: 'hashed_password_secret'
)
user.save

user.tags << 'admin' << 'developer'
user.permissions << 'read' << 'write'

puts "=== Familia JSON Serialization Patterns ==="
puts

# Pattern 1: Direct object serialization (always available)
puts "1. Direct Familia Object Serialization:"
puts "   user.as_json  # Secure - only public fields"
p user.as_json
puts "   user.to_json  # Uses Familia::JsonSerializer (OJ strict mode)"
puts user.to_json
puts

puts "   user.tags.as_json  # DataType objects work too"
p user.tags.as_json
puts "   user.tags.to_json"
puts user.tags.to_json
puts

# Pattern 2: Manual mixed serialization (current secure pattern)
puts "2. Manual Mixed Serialization (Current Pattern):"
mixed_data = {
  user: user.as_json,
  tags: user.tags.as_json,
  permissions: user.permissions.as_json,
  meta: { timestamp: Time.now.to_i }
}
puts "   Manual preparation + JsonSerializer.dump:"
puts Familia::JsonSerializer.dump(mixed_data)
puts

# Pattern 3: Opt-in refinement for Hash/Array (new convenience feature)
puts "3. Opt-in Refinement Pattern (Developer Convenience):"
puts "   # Add this line to enable refinements in your file:"
puts "   using Familia::Refinements::DearJson"
puts

# Demonstrate the refinement
require_relative '../lib/familia/refinements/dear_json'
using Familia::Refinements::DearJson

mixed_hash = {
  user: user,                    # Familia object (will call as_json)
  tags: user.tags,              # Familia DataType (will call as_json)
  meta: { timestamp: Time.now.to_i }  # Plain hash (passes through)
}

mixed_array = [
  user,                         # Familia object
  user.tags,                   # Familia DataType
  { type: 'example' },         # Plain hash
  'metadata'                   # Plain string
]

puts "   # Now Hash and Array have secure to_json using Familia::JsonSerializer"
puts "   mixed_hash.to_json:"
puts mixed_hash.to_json
puts

puts "   mixed_array.to_json:"
puts mixed_array.to_json
puts

# Pattern 4: Security demonstration
puts "4. Security Features (Always Active):"
puts "   # Encrypted fields are automatically concealed"
puts "   # This is what user.password_hash looks like:"
puts "   user.password_hash.class # => #{user.password_hash.class}"
puts "   user.password_hash.to_s  # => #{user.password_hash.to_s}"
puts

begin
  user.password_hash.to_json
rescue Familia::SerializerError => e
  puts "   user.password_hash.to_json # => #{e.class}: #{e.message}"
end
puts

puts "   # Only public fields appear in JSON (password_hash is excluded):"
puts "   user.as_json.keys # => #{user.as_json.keys}"
puts

puts "5. Framework Integration Examples:"
puts "   # Rails controller"
puts "   def show"
puts "     render json: user  # Works with as_json/to_json"
puts "   end"
puts
puts "   # Sinatra/Roda response"
puts "   get '/user/:id' do"
puts "     content_type :json"
puts "     user.to_json  # Direct serialization"
puts "   end"
puts
puts "   # API response with refinement"
puts "   using Familia::Refinements::DearJson"
puts "   response = {"
puts "     user: user,"
puts "     meta: { version: '1.0' }"
puts "   }"
puts "   response.to_json  # Handles mixed Familia/core objects"
puts

puts "=== Summary ==="
puts "✅ Security: All JSON serialization uses OJ strict mode"
puts "✅ Encrypted fields: Automatically concealed (ConcealedString protection)"
puts "✅ Public fields only: Horreum objects expose only defined fields"
puts "✅ DataType support: Lists, sets, etc. serialize their contents"
puts "✅ Developer experience: Standard Ruby JSON interface (as_json/to_json)"
puts "✅ Opt-in convenience: Refinements for Hash/Array when desired"
puts "✅ Framework compatible: Works with Rails, Sinatra, Roda, etc."
