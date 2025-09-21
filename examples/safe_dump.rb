#!/usr/bin/env ruby

# examples/safe_dump.rb
#
# Demonstrates the SafeDump feature with the new DSL methods.
# SafeDump allows you to control which fields are exposed when
# serializing objects, preventing accidental exposure of sensitive data.

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'familia'

# Configure connection
Familia.uri = 'redis://localhost:6379/15'

puts '=== SafeDump Feature Examples ==='
puts

# Example 1: Basic SafeDump with simple fields
class User < Familia::Horreum
  feature :safe_dump

  identifier_field :email
  field :email
  field :first_name
  field :last_name
  field :password_hash # Sensitive - not included in safe dump
  field :ssn # Sensitive - not included in safe dump
  field :created_at

  # Define safe dump fields using the new DSL
  safe_dump_field :email
  safe_dump_field :first_name
  safe_dump_field :last_name
  safe_dump_field :created_at
end

puts 'Example 1: Basic SafeDump'
user = User.new(
  email: 'alice@example.com',
  first_name: 'Alice',
  last_name: 'Smith',
  password_hash: 'secret123',
  ssn: '123-45-6789',
  created_at: Familia.now.to_i
)

puts "Full object data: #{user.to_h}"
puts "Safe dump: #{user.safe_dump}"
puts 'Notice: password_hash and ssn are excluded'
puts

# Example 2: SafeDump with computed fields using callables
class Product < Familia::Horreum
  feature :safe_dump

  identifier_field :sku
  field :sku
  field :name
  field :price_cents      # Store price in cents internally
  field :cost_cents       # Sensitive - don't expose
  field :inventory_count
  field :category
  field :created_at

  # Mix simple fields with computed fields
  safe_dump_field :sku
  safe_dump_field :name
  safe_dump_field :category
  safe_dump_field :created_at

  # Computed fields using callables
  safe_dump_field :price, ->(product) { "$#{format('%.2f', product.price_cents.to_i / 100.0)}" }
  safe_dump_field :in_stock, ->(product) { product.inventory_count.to_i > 0 }
  safe_dump_field :display_name, ->(product) { "#{product.name} (#{product.sku})" }
end

puts 'Example 2: SafeDump with computed fields'
product = Product.new(
  sku: 'WIDGET-001',
  name: 'Super Widget',
  price_cents: 1599,     # $15.99
  cost_cents: 800,       # $8.00 - sensitive, not exposed
  inventory_count: 25,
  category: 'widgets',
  created_at: Familia.now.to_i
)

puts "Full object data: #{product.to_h}"
puts "Safe dump: #{product.safe_dump}"
puts 'Notice: price converted to dollars, in_stock computed, cost_cents hidden'
puts

# Example 3: SafeDump with multiple field definition styles
class Order < Familia::Horreum
  feature :safe_dump

  identifier_field :order_id
  field :order_id
  field :customer_email
  field :status
  field :total_cents
  field :payment_method
  field :credit_card_number  # Very sensitive!
  field :processing_notes    # Internal only
  field :created_at
  field :shipped_at

  # Mix of individual fields and batch definitions
  safe_dump_field :order_id
  safe_dump_field :customer_email
  safe_dump_field :status

  # Define multiple fields at once
  safe_dump_fields :created_at, :shipped_at

  # Computed fields using hash syntax
  safe_dump_fields(
    { total: ->(order) { "$#{format('%.2f', order.total_cents.to_i / 100.0)}" } },
    { payment_type: ->(order) { order.payment_method&.split('_')&.first&.capitalize } }
  )

  def customer_obscured_email
    email = customer_email.to_s
    return email if email.length < 3

    local, domain = email.split('@', 2)
    return email unless domain

    obscured_local = local[0] + ('*' * [local.length - 2, 0].max) + local[-1]
    "#{obscured_local}@#{domain}"
  end
end

puts 'Example 3: Multiple definition styles'
order = Order.new(
  order_id: 'ORD-2024-001',
  customer_email: 'customer@example.com',
  status: 'shipped',
  total_cents: 2499, # $24.99
  payment_method: 'credit_card',
  credit_card_number: '4111-1111-1111-1111', # Never expose this!
  processing_notes: 'Rush order - expedite shipping',
  created_at: Familia.now.to_i - 86_400, # Yesterday
  shipped_at: Familia.now.to_i - 3600 # 1 hour ago
)

puts "Full object data: #{order.to_h}"
puts "Safe dump: #{order.safe_dump}"
puts 'Notice: credit card and internal notes excluded, computed fields included'
puts

# Example 4: SafeDump with nested objects
class Address < Familia::Horreum
  feature :safe_dump

  identifier_field :id
  field :id
  field :street
  field :city
  field :state
  field :zip_code
  field :country

  # Simple address fields
  safe_dump_fields :street, :city, :state, :zip_code, :country
end

class Customer < Familia::Horreum
  feature :safe_dump

  identifier_field :id
  field :id
  field :name
  field :email
  field :phone
  field :billing_address_id
  field :shipping_address_id
  field :account_balance_cents
  field :credit_limit_cents   # Sensitive
  field :internal_notes       # Internal only

  safe_dump_field :id
  safe_dump_field :name
  safe_dump_field :email
  safe_dump_field :phone

  # Nested object handling - load and safe_dump related addresses
  safe_dump_field :billing_address, lambda { |customer|
    addr_id = customer.billing_address_id
    addr_id ? Address.load(addr_id)&.safe_dump : nil
  }

  safe_dump_field :shipping_address, lambda { |customer|
    addr_id = customer.shipping_address_id
    addr_id ? Address.load(addr_id)&.safe_dump : nil
  }

  safe_dump_field :account_balance, lambda { |customer|
    "$#{format('%.2f', customer.account_balance_cents.to_i / 100.0)}"
  }
end

puts 'Example 4: SafeDump with nested objects'

# Create addresses first
billing = Address.new(
  id: 'addr_1',
  street: '123 Main St',
  city: 'Anytown',
  state: 'CA',
  zip_code: '90210',
  country: 'USA'
)
billing.save

shipping = Address.new(
  id: 'addr_2',
  street: '456 Oak Ave',
  city: 'Somewhere',
  state: 'NY',
  zip_code: '10001',
  country: 'USA'
)
shipping.save

customer = Customer.new(
  id: 'cust_123',
  name: 'Bob Johnson',
  email: 'bob@example.com',
  phone: '555-1234',
  billing_address_id: 'addr_1',
  shipping_address_id: 'addr_2',
  account_balance_cents: 15_000,  # $150.00
  credit_limit_cents: 100_000,    # $1000.00 - sensitive!
  internal_notes: 'VIP customer - handle with care'
)

puts 'Customer safe dump:'
puts JSON.pretty_generate(customer.safe_dump)
puts 'Notice: Nested addresses included, sensitive credit limit excluded'
puts

# Example 5: Introspection methods
puts 'Example 5: SafeDump introspection'
puts "User safe dump field names: #{User.safe_dump_field_names}"
puts "Product safe dump field names: #{Product.safe_dump_field_names}"
puts "Order safe dump field names: #{Order.safe_dump_field_names}"
puts

puts "User safe dump field map keys: #{User.safe_dump_field_map.keys}"
puts "All Product safe dump fields are callable: #{Product.safe_dump_field_map.values.all? do |v|
  v.respond_to?(:call)
end}"
puts

# Example 6: Legacy compatibility methods
puts 'Example 6: Legacy compatibility'
puts "Using legacy safe_dump_fields getter: #{User.safe_dump_fields}"
puts 'Setting fields with set_safe_dump_fields:'

class LegacyModel < Familia::Horreum
  feature :safe_dump
  identifier_field :id
  field :id
  field :name
  field :value
end

LegacyModel.set_safe_dump_fields(:id, :name)
puts "LegacyModel fields after set_safe_dump_fields: #{LegacyModel.safe_dump_fields}"

# Clean up
puts
puts '=== Cleaning up test data ==='
[User, Product, Order, Address, Customer, LegacyModel].each do |klass|
  klass.dbclient.del(klass.dbclient.keys("#{klass.name.downcase}:*"))
rescue StandardError => e
  puts "Error cleaning #{klass}: #{e.message}"
end

puts 'SafeDump examples completed!'
