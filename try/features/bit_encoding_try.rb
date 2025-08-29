# Setup
require_relative '../helpers/test_helpers'

# Need to require score encoding first since permission management depends on it
# and the test helpers might not include all relationship features
require_relative '../../lib/familia/features/relationships/score_encoding'
require_relative '../../lib/familia/features/relationships/permission_management'

# Define a test domain class that includes permission management
class TestCustomDomain < Familia::Horreum
  include Familia::Features::Relationships::PermissionManagement

  feature :expiration

  # Enable permission tracking
  permission_tracking :user_permissions

  class_sorted_set :values

  identifier_field :display_domain

  field :display_domain
  field :custid
  field :created

  # Track in sorted sets with permissions
  def add_to_customer(customer, *permissions)
    permissions = [:read] if permissions.empty?
    score = Familia::Features::Relationships::ScoreEncoding.encode_score(created || Time.now, permissions)
    customer.custom_domains.add(score, display_domain)
    grant(customer, *permissions)
  end

  def remove_from_customer(customer)
    customer.custom_domains.zrem(display_domain)
    revoke(customer, :read, :write, :edit, :delete, :configure, :transfer, :admin)
  end

  def customer_permissions(customer)
    permissions_for(customer)
  end
end

# Test basic bit encoding
@domain = TestCustomDomain.new(display_domain: "example.com", created: Time.at(1704067200))
@customer = Customer.new(custid: "test123")

# Clear any existing data
@customer.custom_domains.clear
@domain.clear_all_permissions if @domain.respond_to?(:clear_all_permissions)

## Test basic bit encoding with timestamp
score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), [:read, :write])
#=> 1704067200.005

## Test permission decoding returns correct timestamp
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(1704067200.005)
decoded[:timestamp]
#=> 1704067200

## Test permission decoding returns correct permission bits
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(1704067200.005)
decoded[:permissions]
#=> 5

## Test permission decoding returns correct permission list
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(1704067200.005)
decoded[:permission_list].sort
#=> [:read, :write]

## Test permission checking - should have read permission
Familia::Features::Relationships::ScoreEncoding.has_permission?(1704067200.005, :read)
#==> true

## Test permission checking - should not have delete permission (debug)
result = Familia::Features::Relationships::ScoreEncoding.has_permission?(1704067200.005, :delete)
puts "DEBUG: has_permission result = #{result.inspect}"
!result
#==> true

## Test adding permissions to existing score
new_score = Familia::Features::Relationships::ScoreEncoding.add_permissions(1704067200.005, :delete)
#=> 1704067200.037

## Test verifying added permission
Familia::Features::Relationships::ScoreEncoding.has_permission?(1704067200.037, :delete)
#==> true

## Test removing permissions
reduced = Familia::Features::Relationships::ScoreEncoding.remove_permissions(1704067200.037, :write)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(reduced)
decoded[:permission_list].sort
#=> [:delete, :read]

## Test encoding with single permission symbol
read_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), :read)
#=> 1704067200.001

## Test encoding with permission role
admin_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), :admin)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(admin_score)
decoded[:permissions]
#=> 255

## Test permission range functionality
range = Familia::Features::Relationships::ScoreEncoding.permission_range([:read], [:read, :write])
[range[0], range[1]]
#=> [0.001, 0.005]

## Test granting permissions to user via CustomDomain
@domain.grant(@customer, :read, :write, :edit)
@domain.can?(@customer, :read)
#==> true

## Test checking multiple permissions
@domain.can?(@customer, :read, :write)
#==> true

## Test checking non-granted permission
!@domain.can?(@customer, :delete)
#==> true

## Test revoking specific permissions
@domain.revoke(@customer, :write)
!@domain.can?(@customer, :write)
#==> true

## Test checking remaining permissions after revocation
@domain.can?(@customer, :read)
#==> true

@domain.can?(@customer, :edit)
#==> true

## Test getting all permissions for user
perms = @domain.permissions_for(@customer)
perms.sort
#=> [:edit, :read]

## Test adding permissions to existing user permissions
@domain.add_permission(@customer, :configure, :delete)
updated_perms = @domain.permissions_for(@customer)
updated_perms.sort
#=> [:configure, :delete, :edit, :read]

## Test setting exact permissions (replaces existing)
@domain.set_permissions(@customer, :read, :admin)
final_perms = @domain.permissions_for(@customer)
final_perms.sort
#=> [:admin, :read]

## Test complex permission combinations with array encoding and bit calculation
perms = [:read, :delete, :configure]
score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), perms)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(score)

# Test permission list
permission_list = decoded[:permission_list].sort
expected_bits = 1 + 32 + 16  # read + delete + configure = 49
bits_match = decoded[:permissions] == expected_bits

[permission_list, bits_match]
#=> [[:configure, :delete, :read], true]

## Test predefined role permissions
editor_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), :editor)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(editor_score)
decoded[:permission_list].sort
#=> [:edit, :read, :write]

## Test moderator role includes delete permission
moderator_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), :moderator)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(moderator_score)
decoded[:permission_list].include?(:delete)
#==> true

## Test clearing all permissions for user
@domain.set_permissions(@customer)
@domain.permissions_for(@customer).empty?
#==> true

## Test all_permissions method
@domain2 = TestCustomDomain.new(display_domain: "test2.com")
@customer2 = Customer.new(custid: "test456")
@domain2.grant(@customer, :read)
@domain2.grant(@customer2, :read, :write)
all_perms = @domain2.all_permissions
all_perms.keys.sort
#=> ["test123", "test456"]

## Test permission validation - bits must be 0-255
begin
  Familia::Features::Relationships::ScoreEncoding.encode_score(Time.now, 256)
rescue ArgumentError => e
  e.message
end
#=> "Permission bits must be 0-255"

## Test score range with time bounds
start_time = Time.at(1704067200)
end_time = Time.at(1704067260)
range = Familia::Features::Relationships::ScoreEncoding.score_range(start_time, end_time, min_permissions: [:read])
range[0]
#=> 1704067200.001

## Test CustomDomain integration with customer
@domain.add_to_customer(@customer, :read, :write)
@customer.custom_domains.score(@domain.display_domain) > 0
#==> true

@domain.customer_permissions(@customer).sort
#=> [:read, :write]

## Test boundary conditions - minimum permissions (0)
zero_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), 0)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(zero_score)
decoded[:permissions]
#=> 0

## Test boundary conditions - maximum permissions (255)
max_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), 255)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(max_score)
decoded[:permissions]
#=> 255

## Test edge case - empty permission array
empty_perms_score = Familia::Features::Relationships::ScoreEncoding.encode_score(Time.at(1704067200), [])
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(empty_perms_score)
decoded[:permissions]
#=> 0

## Test edge case - invalid permission bits (negative)
begin
  Familia::Features::Relationships::ScoreEncoding.encode_score(Time.now, -1)
rescue ArgumentError => e
  e.message
end
#=> "Permission bits must be 0-255"

## Test edge case - concurrent permission modifications
@domain3 = TestCustomDomain.new(display_domain: "concurrent.com")
@domain3.grant(@customer, :read)
original_perms = @domain3.permissions_for(@customer)
@domain3.add_permission(@customer, :write)
@domain3.revoke(@customer, :read)
updated_perms = @domain3.permissions_for(@customer)
[original_perms, updated_perms]
#=> [[:read], [:write]]

## Test edge case - permissions with nil/invalid user
@domain4 = TestCustomDomain.new(display_domain: "nil-test.com")
@domain4.grant(nil, :read)
@domain4.can?(nil, :read)
#==> true

## Test edge case - very large numbers still work with timestamp
large_timestamp = Time.at(2147483647)  # Max 32-bit timestamp
score = Familia::Features::Relationships::ScoreEncoding.encode_score(large_timestamp, :read)
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(score)
[decoded[:timestamp], decoded[:permission_list]]
#=> [2147483647, [:read]]

## Test edge case - float score precision
# Should handle precise decimal values correctly
precise_score = 1704067200.123
decoded = Familia::Features::Relationships::ScoreEncoding.decode_score(precise_score)
decoded[:permissions]
#=> 123

## Test edge case - score range with no minimum permissions
range = Familia::Features::Relationships::ScoreEncoding.score_range(nil, nil)
range
#=> ["-inf", "+inf"]

## Test edge case - all permissions cleared and re-added
@domain5 = TestCustomDomain.new(display_domain: "clear-test.com")
@domain5.grant(@customer, :admin)
@domain5.can?(@customer, :admin)
#==> true

## Test clearing all permissions
@domain5.clear_all_permissions
!@domain5.can?(@customer, :admin)
#==> true

@domain5.grant(@customer, :read)
@domain5.can?(@customer, :read)
#==> true

## Test edge case - permission range calculations
min_range = Familia::Features::Relationships::ScoreEncoding.permission_range([:read])
max_range = Familia::Features::Relationships::ScoreEncoding.permission_range([], [:admin])
[min_range[0], max_range[1]]
#=> [0.001, 0.128]

## Test edge case - decode invalid score types
Familia::Features::Relationships::ScoreEncoding.decode_score(nil)[:permissions]
#=> 0

Familia::Features::Relationships::ScoreEncoding.decode_score("invalid")[:permissions]
#=> 0

## Test edge case - has_permission with invalid permission
!Familia::Features::Relationships::ScoreEncoding.has_permission?(1704067200.001, :nonexistent)
#==> true

## Test stress test - multiple users with different permission sets
@stress_domain = TestCustomDomain.new(display_domain: "stress.com")
@stress_user1 = Customer.new(custid: "stress_user1")
@stress_user2 = Customer.new(custid: "stress_user2")
@stress_domain.grant(@stress_user1, :read)
@stress_domain.grant(@stress_user2, :read, :write, :edit, :delete, :configure, :transfer, :admin)

## Test verify limited user permissions
@stress_domain.can?(@stress_user1, :read)
#==> true

## Test verify admin user has all permissions
@stress_domain.can?(@stress_user2, :admin)
#==> true

## Test verify limited user does not have admin
!@stress_domain.can?(@stress_user1, :admin)
#==> true

# Teardown
@customer.custom_domains.clear
@domain.clear_all_permissions if @domain.respond_to?(:clear_all_permissions)
@domain2.clear_all_permissions if @domain2.respond_to?(:clear_all_permissions)
