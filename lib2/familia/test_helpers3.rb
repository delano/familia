# rubocop:disable all


class Customer

  include Familia

  index :custid

  field :custid
  field :sessid
  field :secrets_created
  field :created
  field :role
  field :updated
  field :passphrase_encryption
  field :passphrase
  field :key
  field :verified
  field :apitoken
  field :planid

end


__END__


  feature :safe_dump
  feature :api_version

  class_sorted_set :values  #@values = Familia::SortedSet.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: 6
  class_hashkey :domains  #@domains = Familia::HashKey.new name.to_s.downcase.gsub('::', Familia.delim).to_sym, db: 6

  hashkey :stripe_customer

  sorted_set :metadata
  sorted_set :custom_domains

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
