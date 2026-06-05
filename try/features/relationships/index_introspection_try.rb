# try/features/relationships/index_introspection_try.rb
#
# Project-wide relationship introspection: Familia.index_descriptors /
# unique_indexes / multi_indexes / participation_descriptors, the
# IndexDescriptor behavior (each_record, rebuild!, stale_format?), and the
# stale-index boot guard (stale_indexes / assert_indexes_current!).

require_relative '../../support/helpers/test_helpers'

Familia.enable_database_logging = true

class ::IxUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :username

  unique_index :email, :email_lookup
  unique_index :username, :username_lookup, query: false

  class_sorted_set :instances, reference: true
end

# Define IxCompany before IxEmployee so the within: reference resolves.
class ::IxCompany < Familia::Horreum
  feature :relationships

  identifier_field :company_id
  field :company_id

  sorted_set :employees

  class_sorted_set :instances, reference: true
end

class ::IxEmployee < Familia::Horreum
  feature :relationships

  identifier_field :emp_id
  field :emp_id
  field :badge_number
  field :department

  unique_index :badge_number, :badge_index, within: IxCompany
  multi_index :department, :dept_index, within: IxCompany

  participates_in IxCompany, :employees, score: :emp_id

  class_sorted_set :instances, reference: true
end

# Setup data
@u1 = IxUser.new(user_id: 'u1', email: 'u1@test.com', username: 'alice')
@u1.save
@u2 = IxUser.new(user_id: 'u2', email: 'u2@test.com', username: 'bob')
@u2.save

@company = IxCompany.new(company_id: 'c1')
@company.save
@e1 = IxEmployee.new(emp_id: 'e1', badge_number: 'B1', department: 'eng')
@e1.save
@e1.add_to_ix_company_employees(@company)
@e1.add_to_ix_company_badge_index(@company)

# =============================================
# 1. legacy_json_encoded? predicate (shared with the read path)
# =============================================

## Detects JSON-encoded identifiers
Familia.legacy_json_encoded?('"u1"')
#=> true

## Rejects raw identifiers
Familia.legacy_json_encoded?('u1')
#=> false

## Rejects non-strings, nil, and empty quotes
[Familia.legacy_json_encoded?(nil), Familia.legacy_json_encoded?('""'), Familia.legacy_json_encoded?(42)]
#=> [false, false, false]

# =============================================
# 2. Project-wide aggregators
# =============================================

## unique_indexes finds both of IxUser's unique indexes
Familia.unique_indexes(owner: IxUser).map(&:index_name).sort
#=> [:email_lookup, :username_lookup]

## all IxUser unique descriptors report :unique cardinality
Familia.unique_indexes(owner: IxUser).map(&:cardinality).uniq
#=> [:unique]

## multi_indexes finds IxEmployee's dept_index
Familia.multi_indexes(owner: IxEmployee).map(&:index_name)
#=> [:dept_index]

## index_descriptors returns both cardinalities for IxEmployee
Familia.index_descriptors(owner: IxEmployee).map(&:cardinality).sort
#=> [:multi, :unique]

## class_level: true filters to class-level indexes only
Familia.unique_indexes(owner: IxEmployee, class_level: true)
#=> []

## class_level: false returns instance-scoped indexes
Familia.unique_indexes(owner: IxEmployee, class_level: false).map(&:index_name)
#=> [:badge_index]

# =============================================
# 3. Descriptor metadata
# =============================================

## coordinate is "Owner:index_name"
Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :email_lookup }.coordinate
#=> "IxUser:email_lookup"

## class-level unique index is class_level?
Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :email_lookup }.class_level?
#=> true

## instance-scoped index is not class_level?
Familia.unique_indexes(owner: IxEmployee).find { |i| i.index_name == :badge_index }.class_level?
#=> false

## query? reflects the query: option (username_lookup is query: false)
Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :username_lookup }.query?
#=> false

## field is exposed
Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :email_lookup }.field
#=> :email

# =============================================
# 4. each_record hides the backing-collection mechanics
# =============================================

## class-level unique each_record yields the indexed records
@emails = []
Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :email_lookup }
       .each_record { |u| @emails << u.user_id }
@emails.sort
#=> ["u1", "u2"]

## instance-scoped each_record yields records when given scope:
@badges = []
Familia.unique_indexes(owner: IxEmployee).find { |i| i.index_name == :badge_index }
       .each_record(scope: @company) { |e| @badges << e.emp_id }
@badges
#=> ["e1"]

## instance-scoped each_record without scope: raises a clear error
begin
  Familia.unique_indexes(owner: IxEmployee).find { |i| i.index_name == :badge_index }.each_record { |x| x }
  'no raise'
rescue Familia::Problem => e
  e.message.include?('instance-scoped')
end
#=> true

## multi_index each_record without value: raises a clear error
begin
  Familia.multi_indexes(owner: IxEmployee).first.each_record(scope: @company) { |x| x }
  'no raise'
rescue ArgumentError => e
  e.message.include?('multi_index')
end
#=> true

# =============================================
# 5. rebuild! delegates to the generated rebuilder
# =============================================

## rebuild! on a class-level unique index returns the count
IxUser.email_lookup.clear
count = Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :email_lookup }.rebuild!
[count, IxUser.email_lookup.size]
#=> [2, 2]

## rebuild! on an instance-scoped index without scope: raises
begin
  Familia.unique_indexes(owner: IxEmployee).find { |i| i.index_name == :badge_index }.rebuild!
  'no raise'
rescue Familia::Problem => e
  e.message.include?('instance-scoped')
end
#=> true

# =============================================
# 6. Stale-format detection (the boot guard) — gap #3
# =============================================

## freshly written indexes are not stale
Familia.unique_indexes(owner: IxUser).all?(&:format_current?)
#=> true

## stale_indexes is empty for current data
Familia.stale_indexes(owner: IxUser)
#=> []

## assert_indexes_current! passes for current data
Familia.assert_indexes_current!(owner: IxUser)
#=> true

## injecting a pre-2.10.0 JSON-encoded value makes the index stale
hk = IxUser.email_lookup
hk.dbclient.hset(hk.dbkey, 'legacy@test.com', '"legacy_uid"')
Familia.unique_indexes(owner: IxUser).find { |i| i.index_name == :email_lookup }.stale_format?
#=> true

## stale_indexes now reports the offending index by coordinate
Familia.stale_indexes(owner: IxUser).map(&:coordinate)
#=> ["IxUser:email_lookup"]

## assert_indexes_current! raises naming the stale coordinate
begin
  Familia.assert_indexes_current!(owner: IxUser)
  'no raise'
rescue Familia::Problem => e
  e.message.include?('IxUser:email_lookup')
end
#=> true

## assert_indexes_current! with on_stale: :warn returns false instead of raising
Familia.assert_indexes_current!(owner: IxUser, on_stale: :warn)
#=> false

## the v2.10.0 sweep: rebuilding stale indexes restores current format
Familia.stale_indexes(owner: IxUser).each(&:rebuild!)
Familia.stale_indexes(owner: IxUser)
#=> []

## guard passes again after the rebuild sweep
Familia.assert_indexes_current!(owner: IxUser)
#=> true

# =============================================
# 7. Participation introspection
# =============================================

## participation_descriptors pairs owner with its participation relationships
Familia.participation_descriptors(owner: IxEmployee).map { |_klass, rel| rel.collection_name }
#=> [:employees]

# Teardown
IxUser.email_lookup.clear
IxUser.username_lookup.clear
IxUser.instances.clear
@company.badge_index.clear
@company.employees.clear
@company.dept_index_for('eng').clear rescue nil
IxCompany.instances.clear
IxEmployee.instances.clear
