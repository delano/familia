# Customer Tryouts
require_relative '../lib/familia'
require_relative './test_helpers'

# Setup
@now = Time.now.to_f
@customer = Customer.new
@customer.custid = "test@example.com"
@customer.email = "test@example.com"
@customer.role = "user"
@customer.key = "abc123"
@customer.planid = "basic"
@customer.created = Time.now.to_i
@customer.updated = Time.now.to_i

## Customer can be saved
@customer.save
#=> true

## Customer can be retrieved by identifier
retrieved_customer = Customer.from_redis("test@example.com")
retrieved_customer.custid
#=> "test@example.com"

## Customer fields can be accessed
@customer.email
#=> "test@example.com"

## Customer role can be set and retrieved
@customer.role = "admin"
@customer.role
#=> "admin"

## Customer can update fields
@customer.planid = "premium"
@customer.save
ident = @customer.identifier
Customer.from_redis(ident).planid
#=> "premium"

## Customer can increment secrets_created counter
@customer.secrets_created.clear
@customer.secrets_created.increment
@customer.secrets_created.value
#=> '1'

## Customer can add custom domain via add method
@customer.custom_domains.add(@now, "example.org")
@customer.custom_domains.members.include?("example.org")
#=> true

## Customer can retrieve custom domain score via score method
@customer.custom_domains.score("example.org")
#=> @now

## Customer can add custom domain via []= method
@customer.custom_domains["example2.org"] = @now
@customer.custom_domains.members.include?("example2.org")
#=> true

## Customer can retrieve custom domain score via []
@customer.custom_domains["example.org"]
#=> @now


## Customer can store timeline
@customer.timeline["last_login"] = @now
@customer.timeline["last_login"].to_i.positive?
#=> true

## Customer can be added to class-level sorted set
Customer.instances << @customer
Customer.instances.member?(@customer)
#=> true

## Customer can be removed from class-level sorted set
Customer.instances.delete(@customer)
Customer.instances.member?(@customer)
#=> false

## Customer can add a session
@customer.sessions << "session123"
@customer.sessions.members.include?("session123")
#=> true

## Customer can set and get password reset information
@customer.password_reset["token"] = "reset123"
@customer.password_reset["token"]
#=> "reset123"

## Customer can be destroyed
ret = @customer.destroy!
cust = Customer.from_redis("test@example.com")
exists = Customer.exists?("test@example.com")
[ret, cust.nil?, exists]
#=> [true, true, false]

## Customer.destroy! can be called on an already destroyed object
@customer.destroy!
#=> false

## Customer.destroy! makes only one call to Redis
RedisCommandCounter.count_commands { @customer.destroy! }
#=> 1


# Teardown
Customer.instances.clear
