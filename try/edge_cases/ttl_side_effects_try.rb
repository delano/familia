require_relative '../helpers/test_helpers'

# Test TTL side effects
group 'TTL Side Effects Edge Cases'

setup do
  @session_class = Class.new(Familia::Horreum) do
    identifier_field :session_id
    field :name
    field :data
    feature :expiration
    default_expiration 300 # 5 minutes
  end
end

try 'field update unintentionally resets TTL' do
  session = @session_class.new(session_id: 'test123', name: 'Session')
  session.save

  # Set shorter TTL
  session.expire(60)
  original_ttl = session.realttl

  # Update field - this may reset TTL unexpectedly
  session.name = 'Updated Session'
  session.save

  new_ttl = session.realttl

  # TTL should remain short but may have been reset
  new_ttl > original_ttl # Indicates TTL side effect
ensure
  session&.delete!
end

try 'batch update preserves TTL with flag' do
  session = @session_class.new(session_id: 'test124')
  session.save
  session.expire(60)

  original_ttl = session.realttl

  # Use update_expiration: false to preserve TTL
  session.batch_update({ name: 'Batch Updated' }, update_expiration: false)

  new_ttl = session.realttl

  (original_ttl - new_ttl).abs < 5 # TTL preserved within tolerance
ensure
  session&.delete!
end
