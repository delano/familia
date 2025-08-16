#!/usr/bin/env ruby

require_relative 'lib/familia'

# Test classes for debugging
class DebugCustomer < Familia::Horreum
  feature :relationships

  identifier_field :custid
  field :custid
  field :name
end

class DebugDomain < Familia::Horreum
  feature :relationships

  identifier_field :domain_id
  field :domain_id
  field :display_domain

  # Simple tracking relationship
  tracked_in DebugCustomer, :domains, score: :domain_id
end

puts "=== Debug Method Generation ==="
puts "DebugDomain methods that include 'debugcustomer':"
puts DebugDomain.instance_methods(false).grep(/debugcustomer/)

puts "\nDebugDomain methods that include 'customer':"
puts DebugDomain.instance_methods(false).grep(/customer/)

puts "\nDebugDomain methods that include 'domain':"
puts DebugDomain.instance_methods(false).grep(/domain/)

puts "\nDebugCustomer methods that include 'domain':"
puts DebugCustomer.instance_methods(false).grep(/domain/)

puts "\nDebugCustomer singleton methods that include 'domain':"
puts DebugCustomer.singleton_methods(false).grep(/domain/)

puts "\nAll DebugDomain instance methods:"
puts DebugDomain.instance_methods(false).sort

puts "\nTracking relationships on DebugDomain:"
puts DebugDomain.tracking_relationships.inspect
