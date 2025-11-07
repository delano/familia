# examples/autoloader/mega_customer.rb
#
# frozen_string_literal: true

require_relative '../../lib/familia'

class MegaCustomer < Familia::Horreum
  include Familia::Features::Autoloader

  field :custid
  field :username
  field :email
  field :fname
  field :lname
  field :display_name
  field :created_at
  field :updated_at

  feature :safe_dump
  feature :deprecated_fields
end
