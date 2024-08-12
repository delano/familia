# rubocop:disable all

require_relative 'familia'

class Subdomain < Familia::HashKey

end


class Customer < Familia::Horreum
  #feature :safe_dump
  #feature :api_version

  class_sorted_set :values
  class_hashkey :domains

  hashkey :stripe_customer
  sorted_set :metadata
  sorted_set :custom_domains

  counter :secrets_created

  identifier :custid

  field :key
  field :custid
  field :sessid
  field :email
  field :role
  field :passphrase_encryption
  field :passphrase
  field :verified
  field :apitoken
  field :planid
  field :created
  field :updated

end
@c = Customer.new
@c.custid = "d@example.com"

class Session < Familia::Horreum
  #include Familia

  identifier :generate_id

  field :shrimp
  field :key
  field :custid
  field :useragent
  field :authenticated
  field :sessid
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
    @external_identifier ||= elements.gibbler.base(36)
    OT.ld "[Session.external_identifier] sess identifier input: #{elements.inspect} (result: #{@external_identifier})"
    @external_identifier
  end

end
@s = Session.new

class CustomDomain < Familia::Horreum
  #include Familia

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
    join(:display_domain, :custid).gibbler.shorten
  end
end
@d = CustomDomain.new
@d.display_domain = "example.com"
@d.custid = @c.custid



__END__



 # NOTE: The SafeDump mixin caches the safe_dump_field_map so updating this list
  # with hot reloading in dev mode will not work. You will need to restart the
  # server to see the changes.
  @safe_dump_fields = [
    :custid,
    :role,
    :verified,
    :updated,
    :created,

    :stripe_customer_id,
    :stripe_subscription_id,
    :stripe_checkout_email,

    {plan: ->(cust) { cust.load_plan } }, # safe_dump will be called automatically

    # NOTE: The secrets_created incrementer is null until the first secret
    # is created. See CreateSecret for where the incrementer is called.
    #
    {secrets_created: ->(cust) { cust.secrets_created || 0 } },

    # We use the hash syntax here since `:active?` is not a valid symbol.
    {active: ->(cust) { cust.active? } }
  ]
