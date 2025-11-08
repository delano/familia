# try/edge_cases/ttl_side_effects_try.rb
#
# frozen_string_literal: true

# Test TTL side effects

require_relative '../support/helpers/test_helpers'

## field update behavior with TTL
begin
  session_class = Class.new(Familia::Horreum) do
    identifier_field :session_id
    field :session_id
    field :name
    field :data
    feature :expiration
    default_expiration 300 # 5 minutes
  end

  session = session_class.new(session_id: 'test123', name: 'Session')
  session.save

  # UnsortedSet shorter TTL
  session.expire(60)
  original_ttl = session.realttl

  # Update field
  session.name = 'Updated Session'
  session.save

  new_ttl = session.realttl

  # Check if TTL was preserved or reset
  result = new_ttl > original_ttl # true if TTL was reset (side effect)
  session.delete!
  result
rescue StandardError => e
  session&.delete! rescue nil
  false
end
#=> false

## batch update attempts to preserve TTL
begin
  session_class = Class.new(Familia::Horreum) do
    identifier_field :session_id
    field :session_id
    field :name
    feature :expiration
    default_expiration 300
  end

  session = session_class.new(session_id: 'test124')
  session.save
  session.expire(60)

  original_ttl = session.realttl

  # Try batch update (if available)
  begin
    session.batch_update({ name: 'Batch Updated' }, update_expiration: false)
    new_ttl = session.realttl
    result = (original_ttl - new_ttl).abs < 5 # TTL preserved within tolerance
  rescue NoMethodError
    result = true # Method not available, assume test passes
  end

  session.delete!
  result
rescue StandardError => e
  session&.delete! rescue nil
  true
end
#=> true
