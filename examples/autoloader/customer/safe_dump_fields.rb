# examples/autoloader/customer/safe_dump_fields.rb

module Customer::SafeDumpFields
  safe_dump_fields :custid, :username, :created_at, :updated_at
end
