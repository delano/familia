# frozen_string_literal: true

# try/features/field_groups_try.rb

require_relative '../../lib/familia'

# Define test classes in setup section
class BasicUser < Familia::Horreum
  field_group :personal_info do
    field :name
    field :email
  end
end

class MultiGroupUser < Familia::Horreum
  field_group :personal do
    field :name
    field :email
  end

  field_group :metadata do
    field :created_at
    field :updated_at
  end
end

class EmptyGroupModel < Familia::Horreum
  field_group :placeholder
end

class TransientModel < Familia::Horreum
  feature :transient_fields
  transient_field :api_key
  transient_field :session_token
end

class EncryptedModel < Familia::Horreum
  feature :encrypted_fields
  encrypted_field :password
  encrypted_field :credit_card
end

class MixedGroupsModel < Familia::Horreum
  feature :transient_fields
  transient_field :temp_data

  field_group :custom do
    field :custom_field
  end

  feature :encrypted_fields
  encrypted_field :secret_key
end

class FieldsOutsideGroups < Familia::Horreum
  field :standalone_field

  field_group :grouped do
    field :grouped_field
  end
end

class NoSuchGroup < Familia::Horreum
  field_group :existing do
    field :name
  end
end

class ParentModel < Familia::Horreum
  field_group :base_fields do
    field :id
  end
end

class ChildModel < ParentModel
  field_group :child_fields do
    field :name
  end
end

# Create instances for testing
@user = MultiGroupUser.new(name: 'Alice', email: 'alice@example.com', created_at: Time.now.to_i)
@user2 = BasicUser.new(name: 'Bob', email: 'bob@example.com')

## Manual field groups - basic access via hash
BasicUser.instance_variable_get(:@field_groups)[:personal_info]
#=> [:name, :email]

## Multiple groups - access personal group via hash
MultiGroupUser.instance_variable_get(:@field_groups)[:personal]
#=> [:name, :email]

## Multiple groups - access metadata group via hash
MultiGroupUser.instance_variable_get(:@field_groups)[:metadata]
#=> [:created_at, :updated_at]

## Multiple groups - list all field groups (returns hash)
MultiGroupUser.field_groups.keys.sort
#=> [:metadata, :personal]

## Field groups - fields defined inside groups are tracked
user = MultiGroupUser.new(name: 'Alice', email: 'alice@example.com', created_at: Time.now.to_i)

## Grouped fields - access name field
@user.name
#=> 'Alice'

## Grouped fields - access email field
@user.email
#=> 'alice@example.com'

## Empty group - access via hash
EmptyGroupModel.instance_variable_get(:@field_groups)[:placeholder]
#=> []

## Empty group - list field groups (returns hash)
EmptyGroupModel.field_groups
#=> {placeholder: []}

## Empty group - list field group keys
EmptyGroupModel.field_groups.keys
#=> [:placeholder]

## Transient feature - access via backward compatible method
TransientModel.transient_fields
#=> [:api_key, :session_token]

## Transient feature - access via field_groups hash
TransientModel.instance_variable_get(:@field_groups)[:transient_fields]
#=> [:api_key, :session_token]

## Transient feature - field_groups returns hash with content
TransientModel.field_groups
#=> {transient_fields: [:api_key, :session_token]}

## Transient feature - list field group keys
TransientModel.field_groups.keys
#=> [:transient_fields]

## Encrypted feature - access via backward compatible method
EncryptedModel.encrypted_fields
#=> [:password, :credit_card]

## Encrypted feature - access via field_groups hash
EncryptedModel.instance_variable_get(:@field_groups)[:encrypted_fields]
#=> [:password, :credit_card]

## Encrypted feature - field_groups returns hash with content
EncryptedModel.field_groups
#=> {encrypted_fields: [:password, :credit_card]}

## Encrypted feature - list field group keys
EncryptedModel.field_groups.keys
#=> [:encrypted_fields]

## Mixed groups - list all field group keys
MixedGroupsModel.field_groups.keys.sort
#=> [:custom, :encrypted_fields, :transient_fields]

## Mixed groups - access custom group via hash
MixedGroupsModel.instance_variable_get(:@field_groups)[:custom]
#=> [:custom_field]

## Mixed groups - access transient_fields via backward compatible method
MixedGroupsModel.transient_fields
#=> [:temp_data]

## Mixed groups - access encrypted_fields via backward compatible method
MixedGroupsModel.encrypted_fields
#=> [:secret_key]

## Error: nested field groups
class NestedGroupsModel < Familia::Horreum
  field_group :outer do
    field_group :inner do
      field :bad
    end
  end
end
#=!> Familia::Problem

## Exception during field_group block resets @current_field_group
class ErrorDuringGroup < Familia::Horreum
  begin
    field_group :broken do
      field :first_field
      raise StandardError, "Simulated error"
      field :unreachable_field
    end
  rescue StandardError
    # Swallow the error for testing
  end

  # Field defined after the error should not be in :broken group
  field :after_error
end

ErrorDuringGroup
#=> ErrorDuringGroup

## Exception handling - broken group has only first_field
ErrorDuringGroup.instance_variable_get(:@field_groups)[:broken]
#=> [:first_field]

## Exception handling - after_error field is not in broken group
ErrorDuringGroup.instance_variable_get(:@field_groups)[:broken].include?(:after_error)
#=> false

## Exception handling - after_error is in fields list
ErrorDuringGroup.fields.include?(:after_error)
#=> true

## Exception handling - current_field_group was reset to nil
ErrorDuringGroup.instance_variable_get(:@current_field_group)
#=> nil


## Fields outside - access grouped field group via hash
FieldsOutsideGroups.instance_variable_get(:@field_groups)[:grouped]
#=> [:grouped_field]

## Fields outside - all fields include both grouped and standalone
FieldsOutsideGroups.fields
#=> [:standalone_field, :grouped_field]

## Accessing non-existent field group returns nil
NoSuchGroup.instance_variable_get(:@field_groups)[:nonexistent]
#=> nil

## Inheritance - parent class has its own field groups
ParentModel.field_groups
#=> {base_fields: [:id]}

## Inheritance - child class has its own field groups
ChildModel.field_groups
#=> {child_fields: [:name]}

## Normal field access - get name value
@user2.name
#=> 'Bob'

## Normal field access - get email value
@user2.email
#=> 'bob@example.com'
