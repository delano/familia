# try/helpers/test_helpers.rb

# To enable tracing and debug mode, run with the env vars set.
#
# e.g. FAMILIA_TRACE=1 FAMILIA_DEBUG=1 bundle exec try

require 'digest'

require_relative '../../lib/familia'

Familia.enable_database_logging = true
Familia.enable_database_counter = true

class Bone < Familia::Horreum
  identifier_field :token
  field     :token
  field     :name
  list      :owners
  set       :tags
  zset      :metrics
  hashkey   :props
  string    :value, default: 'GREAT!'
end

class Blone < Familia::Horreum
  feature :safe_dump
  list      :owners
  set       :tags
  zset      :metrics
  hashkey   :props
  string    :value, default: 'GREAT!'
end

class Customer < Familia::Horreum
  logical_database 15 # Use something other than the default DB
  default_expiration 5.years

  feature :safe_dump
  # feature :expiration
  # feature :api_version

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
    { secrets_created: ->(cust) { cust.secrets_created.value || 0 } },

    # We use the hash syntax here since `:active?` is not a valid symbol.
    { active: ->(cust) { cust.active? } }
  ]

  class_sorted_set :values, key: 'onetime:customer'
  class_hashkey :domains

  hashkey :stripe_customer
  sorted_set :timeline
  sorted_set :custom_domains

  counter :secrets_created

  identifier_field :custid

  field :custid
  field :sessid
  field :email
  field :role
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
@c.custid = 'd@example.com'

class Session < Familia::Horreum
  logical_database 14 # don't use Onetime's default DB
  default_expiration 180.minutes

  identifier_field :sessid

  field :sessid
  field :shrimp
  field :custid
  field :useragent
  field :authenticated
  field :ipaddress
  field :created
  field :updated

  def save
    self.sessid ||= Familia.generate_id # Only generates when persisting
    super
  end
end
@s = Session.new

class CustomDomain < Familia::Horreum
  feature :expiration

  class_sorted_set :values

  identifier_field :generate_id

  field :domainid
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
end

@d = CustomDomain.new
@d.display_domain = 'example.com'
@d.custid = @c.custid

class Limiter < Familia::Horreum
  feature :expiration
  feature :quantization

  identifier_field :name
  default_expiration 30.minutes
  field :name

  string :counter, default_expiration: 1.hour, quantize: [10.minutes, '%H:%M', 1_302_468_980]

  def identifier
    @name
  end
end

# # In test:
# using RedactedStringTestHelper

# secret = RedactedString.new("test-key")
# expect(secret.raw).to eq("test-key")
#
# Or with rack
#
# post '/vault' do
#   passphrase = RedactedString.new(request.params['passphrase'])
#   passphrase.expose do |plain|
#     vault.unlock(plain)
#   end
#   # passphrase wiped
# end
#
# NOTE: This will do nothing unless RedactedString is already requried
unless defined?(RedactedString)
  require_relative '../../lib/familia/features/transient_fields/redacted_string'
end
module RedactedStringTestHelper
  refine RedactedString do
    def raw
      # Only available when refinement is used
      @value
    end
  end
end

unless defined?(SingleUseRedactedString)
  require_relative '../../lib/familia/features/transient_fields/single_use_redacted_string'
end
module SingleUseRedactedStringTestHelper
  refine SingleUseRedactedString do
    def raw
      # Only available when refinement is used
      @value
    end
  end
end
