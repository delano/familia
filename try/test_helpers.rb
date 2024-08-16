# rubocop:disable all

require 'digest'
require_relative '../lib/familia'

# ENV['FAMILIA_TRACE'] = '1'
#Familia.debug = true
Familia.enable_redis_logging = true
Familia.enable_redis_counter = true

class Bone < Familia::Horreum
  identifier     [:token, :name]
  field     :token
  field     :name
  list      :owners
  set       :tags
  zset      :metrics
  hashkey   :props
  string    :value, :default => "GREAT!"
end

class Blone < Familia::Horreum
  feature :safe_dump
  list      :owners
  set       :tags
  zset      :metrics
  hashkey   :props
  string    :value, :default => "GREAT!"
end

class Customer < Familia::Horreum
  db 15 # don't use Onetime's default DB
  ttl 5.years

  feature :safe_dump
  #feature :api_version

  # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
  # with hot reloading in dev mode will not work. You will need to restart the
  # server to see the changes.
  @safe_dump_fields = [
    :custid,
    :role,
    :verified,
    :updated,
    :created,

    # NOTE: The secrets_created incrementer is null until the first secret
    # is created. See CreateSecret for where the incrementer is called.
    #
    {secrets_created: ->(cust) { cust.secrets_created.value || 0 } },

    # We use the hash syntax here since `:active?` is not a valid symbol.
    {active: ->(cust) { cust.active? } }
  ]

  class_sorted_set :values, key: 'onetime:customer'
  class_hashkey :domains

  hashkey :stripe_customer
  sorted_set :timeline
  sorted_set :custom_domains

  counter :secrets_created

  identifier :custid

  field :custid
  field :sessid
  field :email
  field :role
  field :key
  field :name
  field :passphrase_encryption
  field :passphrase
  field :verified
  field :apitoken
  field :planid
  field :created
  field :updated
  field :reset_requested #=> Boolean

  hashkey :password_reset #=> Familia::HashKey
  list :sessions #=> Familia::List

  class_list :customers, suffix: []
  class_string :message

  class_zset :instances, class: self, reference: true

  def active?
    verified && !reset_requested
  end
end
@c = Customer.new
@c.custid = "d@example.com"

class Session < Familia::Horreum
  db 14 # don't use Onetime's default DB
  ttl 180.minutes

  identifier :generate_id

  field :sessid
  field :shrimp
  field :custid
  field :useragent
  field :key
  field :authenticated
  field :ipaddress
  field :created
  field :updated

  def generate_id
    @sessid ||= Familia.generate_id
    @sessid
  end

  # The external identifier is used by the rate limiter to estimate a unique
  # client. We can't use the session ID b/c the request agent can choose to
  # not send cookies, or the user can clear their cookies (in both cases the
  # session ID would change which would circumvent the rate limiter). The
  # external identifier is a hash of the IP address and the customer ID
  # which means that anonymous users from the same IP address are treated
  # as the same client (as far as the limiter is concerned). Not ideal.
  #
  # To put it another way, the risk of colliding external identifiers is
  # acceptable for the rate limiter, but not for the session data. Acceptable
  # b/c the rate limiter is a temporary measure to prevent abuse, and the
  # worse case scenario is that a user is rate limited when they shouldn't be.
  # The session data is permanent and must be kept separate to avoid leaking
  # data between users.
  def external_identifier
    elements = []
    elements << ipaddress || 'UNKNOWNIP'
    elements << custid || 'anon'
    @external_identifier ||= Familia.generate_sha_hash(elements)
    Familia.ld "[Session.external_identifier] sess identifier input: #{elements.inspect} (result: #{@external_identifier})"
    @external_identifier
  end

end
@s = Session.new

class CustomDomain < Familia::Horreum

  class_sorted_set :values, key: 'onetime:customdomain:values'

  identifier :derive_id

  field :display_domain
  field :custid
  field :base_domain
  field :subdomain
  field :trd
  field :tld
  field :sld
  field :txt_validation_host
  field :txt_validation_value
  field :status
  field :vhost
  field :verified
  field :created
  field :updated
  field :_original_value

  # Derive a unique identifier for the object based on the display domain and
  # the customer ID. This is used to ensure that the same domain can't be
  # added twice by the same customer while avoiding collisions between customers.
  def derive_id
    Familia.generate_sha_hash(:display_domain, :custid).slice(0, 8)
  end
end
@d = CustomDomain.new
@d.display_domain = "example.com"
@d.custid = @c.custid

class Limiter < Familia::Horreum

  identifier :name
  field :name
  string :counter, :ttl => 1.hour, :quantize => [10.minutes, '%H:%M', 1302468980]

  def identifier
    @name
  end
end
