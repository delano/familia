# examples/autoloader/mega_customer/safe_dump_fields.rb

# Extend the MegaCustomer class to add safe dump fields
class MegaCustomer < Familia::Horreum
  safe_dump_fields :custid, :username, :created_at, :updated_at
end
