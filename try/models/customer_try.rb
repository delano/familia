# try/models/customer_try.rb

# Customer Tryouts
require_relative '../helpers/test_helpers'

# Setup
@now = Time.now.to_f
@customer = Customer.new
@customer.custid = 'test@example.com'
@customer.email = 'test@example.com'
@customer.role = 'user'
# No longer need to set key field - identifier computed from custid
@customer.planid = 'basic'
@customer.created = Time.now.to_i
@customer.updated = Time.now.to_i

## Customer can be saved
@customer.save
#=> true

## Customer can be retrieved by identifier
retrieved_customer = Customer.find_by_id('test@example.com')
retrieved_customer.custid
#=> "test@example.com"

## Customer fields can be accessed
@customer.email
#=> "test@example.com"

## Customer role can be set and retrieved
@customer.role = 'admin'
@customer.role
#=> "admin"

## Customer can update fields
@customer.planid = 'premium'
@customer.save
ident = @customer.identifier
Customer.find_by_id(ident).planid
#=> "premium"

## Customer can increment secrets_created counter
@customer.secrets_created.delete!
@customer.secrets_created.increment
@customer.secrets_created.value
#=> 1

## Customer can add custom domain via add method
@customer.custom_domains.add('example.org', @now)
@customer.custom_domains.members.include?('example.org')
#=> true

## Customer can retrieve custom domain score via score method
@customer.custom_domains.score('example.org')
#=> @now

## Customer can add custom domain via []= method
@customer.custom_domains['example2.org'] = @now
@customer.custom_domains.members.include?('example2.org')
#=> true

## Customer can retrieve custom domain score via []
@customer.custom_domains['example.org']
#=> @now

## Customer can store timeline
@customer.timeline['last_login'] = @now
@customer.timeline['last_login'].to_i.positive?
#=> true

## Customer can be added to class-level sorted set
Customer.instances.add(@customer.identifier)
Customer.instances.member?(@customer)
#=> true

## Customer can be removed from class-level sorted set
Customer.instances.remove(@customer)
Customer.instances.member?(@customer)
#=> false

## Customer can add a session
@customer.sessions << 'session123'
@customer.sessions.members.include?('session123')
#=> true

## Customer can set and get password reset information
@customer.password_reset['token'] = 'reset123'
@customer.password_reset['token']
#=> "reset123"

## Customer can be destroyed
ret = @customer.destroy!
cust = Customer.find_by_id('test@example.com')
exists = Customer.exists?('test@example.com')
[ret, cust.nil?, exists]
#=> [true, true, false]

## Customer.destroy! can be called on an already destroyed object
@customer.destroy!
#=> false

## Customer.logical_database returns the correct database number
Customer.logical_database
#=> 15

## Customer.logical_database returns the correct database number
@customer.logical_database
#=> 15

## @customer.dbclient.connection returns the correct database URI
@customer.dbclient.connection
#=> {:host=>"127.0.0.1", :port=>6379, :db=>15, :id=>"redis://127.0.0.1:6379/15", :location=>"127.0.0.1:6379"}

## @customer.dbclient.uri returns the correct database URI
@customer.secrets_created.logical_database
#=> nil

## @customer.dbclient.uri returns the correct database URI
@customer.secrets_created.dbclient.connection
#=> {:host=>"127.0.0.1", :port=>6379, :db=>15, :id=>"redis://127.0.0.1:6379/15", :location=>"127.0.0.1:6379"}

## Customer.url is nil by default
Customer.uri
#=> nil

## Customer.destroy! makes only one call to Valkey/Redis
DatabaseCommandCounter.count_commands { @customer.destroy! }
#=> 1

## Customer.logical_database returns the correct database number
Customer.instances.logical_database
#=> nil

## Customer.logical_database returns the correct database number
Customer.instances.uri.to_s
#=> 'redis://127.0.0.1/15'

# Teardown
Customer.instances.delete!
