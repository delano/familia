# examples/autoloader/mega_customer.rb

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

  # feature :deprecated_fields
end
