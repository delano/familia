# try/models/customer_safedump_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

# Setup
@now = Time.now.to_i
@customer = Customer.new
@customer.custid = 'test+customer_safedump@example.com'
@customer.email = 'test+customer_safedump@example.com'
@customer.role = 'user'
# No longer need to set key field - identifier computed from custid
@customer.planid = 'basic'
@customer.created = @now
@customer.updated = @now
@customer.verified = true
@customer.reset_requested = false
@customer.save
@safe_dump = @customer.safe_dump

## Customer can be safely dumped
@safe_dump.keys.sort
#=> [:active, :created, :custid, :role, :secrets_created, :updated, :verified]

## Safe dump includes correct custid
@safe_dump[:custid]
#=> "test+customer_safedump@example.com"

## Safe dump includes correct role
@safe_dump[:role]
#=> "user"

## Safe dump includes correct verified status
@safe_dump[:verified]
#=> true

## Safe dump includes correct created timestamp
@safe_dump[:created]
#=> @now

## Safe dump includes correct updated timestamp
@safe_dump[:updated]
#=> @now

## Safe dump includes correct secrets_created count
@customer.secrets_created.increment
@safe_dump = @customer.safe_dump
@safe_dump[:secrets_created]
#=> "1"

## Safe dump includes correct active status when verified and not reset requested
@safe_dump[:active]
#=> true

## Safe dump includes correct active status when not verified
@customer.verified = false
@customer.save
@safe_dump = @customer.safe_dump
@safe_dump[:active]
#=> false

## Safe dump includes correct active status when reset requested
@customer.verified = true
@customer.reset_requested = true
@customer.save
@safe_dump = @customer.safe_dump
@safe_dump[:active]
#=> false

## Safe dump excludes sensitive information (email)
@safe_dump.has_key?(:email)
#=> false

## Safe dump excludes sensitive information (key)
@safe_dump.has_key?(:key)
#=> false

## Safe dump excludes sensitive information (passphrase)
@safe_dump.has_key?(:passphrase)
#=> false

## Safe dump excludes non-specified fields
@safe_dump.has_key?(:planid)
#=> false

# Teardown
@customer.destroy!
@customer.secrets_created.clear
