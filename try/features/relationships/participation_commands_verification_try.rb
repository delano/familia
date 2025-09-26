# try/features/relationships/participation_commands_verification_try.rb
#
# Based on participation reverse index functionality tests.
# Checks the actual commands being sent to redis
#
# TIP: Help debugging by adding to Valkey serviver 8+ config: enable-debug-command yes
#

# Load middleware first
require_relative '../../../lib/middleware/database_middleware'

# Load Familia
require_relative '../../../lib/familia'

# Enable middleware (this will register middleware and clear cached clients)
Familia.enable_database_logging = true
Familia.enable_database_counter = true

# Test classes for reverse index functionality
class ReverseIndexCustomer < Familia::Horreum
  feature :relationships

  identifier_field :customer_id
  field :customer_id
  field :name

  sorted_set :domains
  set :preferred_domains
end

class ReverseIndexDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at

  participates_in ReverseIndexCustomer, :domains, score: :created_at
  participates_in ReverseIndexCustomer, :preferred_domains, bidirectional: true
  class_participates_in :all_domains, score: :created_at
end



## Check there are no commands before we start
captured_commands = DatabaseLogger.commands
#=> []

## Check that no commands run while instantiating horreum model classes
@customer = ReverseIndexCustomer.new(customer_id: 'ri_cust_123', name: 'Reverse Index Test Customer')
@domain1 = ReverseIndexDomain.new(
  domain_id: 'ri_dom_1',
  display_domain: 'example1.com',
  created_at: Time.now.to_f
)
@domain2 = ReverseIndexDomain.new(
  domain_id: 'ri_dom_2',
  display_domain: 'example2.com',
  created_at: Time.now.to_f + 1
)
captured_commands = DatabaseLogger.commands
#=> []

## Check keys when the customer is saved
captured_commands = DatabaseLogger.capture_commands do
  @customer.save
end
captured_commands.size
#=> 2

## Domain saved
captured_commands = DatabaseLogger.capture_commands do
  @domain1.save
end
captured_commands.size
#=> 2

## Domain saved
captured_commands = DatabaseLogger.capture_commands do
  @domain2.save
end
captured_commands.size
#=> 2
