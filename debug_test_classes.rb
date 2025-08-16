#!/usr/bin/env ruby

require_relative 'try/helpers/test_helpers'

# Using the same classes as the test
class TestCustomer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid
  field :name
end

class TestDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain

  # Simple tracking relationship
  tracked_in TestCustomer, :domains, score: :domain_id
end

puts "=== Test Class Method Generation ==="
puts "TestDomain methods that include 'customer':"
puts TestDomain.instance_methods(false).grep(/customer/)

puts "\nClass name: #{TestCustomer.name}"
puts "Downcased: #{TestCustomer.name.downcase}"
