# examples/autoloader/mega_customer/features/deprecated_fields.rb
#
# frozen_string_literal: true

# Extend the MegaCustomer class to organize all of the deprecated fields into one place
class MegaCustomer < Familia::Horreum
  field :favourite_colour
  field :nickname
end
