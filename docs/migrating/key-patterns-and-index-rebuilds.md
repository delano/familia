# Upgrading from 2.13: key patterns and index rebuilds

The first release after 2.13.0 changes how `Familia::Horreum` builds the key
patterns of its KEYS and SCAN methods, which matching keys those methods
count, what the rebuild of a `multi_index` does with a key it cannot write as
a bucket, and what the `multi_index` methods do with a blank field value.
Each section below says what changed and what an application has to change.
Sections that do not apply to your application need no action.

Check your code if it does any of the following:

- passes a glob to `all` or `scan_pattern`, or uses the string `scan_pattern`
  returns in a KEYS or SCAN call of its own
- counts or lists keys with `keys_count`, `scan_count`, `keys_any?`,
  `scan_any?` or `scan_keys`, or rescues `Redis::WrongTypeError` around `all`
  or `rebuild_instances`
- calls the `rebuild_<index>` of a `multi_index`, `repair_multi_indexes!` or
  `repair_all!` and reads what they return
- adds objects whose indexed field is blank to an instance-scoped
  `multi_index`, or looks a blank value up in a `multi_index`
- defines a `Familia::Migration::Model` that leaves `@scan_pattern` unset

## `all` and `scan_pattern` take a literal suffix

`all` and `scan_pattern` build their pattern with the new
`Familia::Horreum.dbkey_pattern(identifier_glob = '*', key_suffix = suffix)`,
which escapes the class prefix, the delimiter and the suffix with
`Familia.escape_glob`. Only the identifier part is a glob. The suffix argument
used to go into the pattern as given:

```ruby
Customer.scan_pattern          # => "customer:*:object", before and after
Customer.scan_pattern('*')     # Before: "customer:*:*"
                               # After:  "customer:*:\\*"
Customer.dbkey_pattern('*', :tags)  # => "customer:*:tags"
```

`Customer.all('*')` matched every key under the class prefix and loaded each
one as an object, so it raised `Redis::WrongTypeError` at the first key that
did not hold a hash, such as the key of a `set` field. It now matches only
keys whose suffix is the one character `*`, and returns `[]` when there is
none. Any other glob suffix changes the same way.

`find_keys` keeps a glob suffix; only the class prefix and delimiter are
escaped. Use it to list every key under the prefix. Like `all`, it uses the
`KEYS` command. For a SCAN, build the pattern from the escaped parts:

```ruby
# Before
Customer.all('*')           # every key under customer:, or WRONGTYPE
Customer.scan_pattern('*')  # => "customer:*:*"

# After
Customer.find_keys('*')     # every key under customer:, with KEYS

delim = Familia.escape_glob(Familia.delim)
pattern = "#{Familia.escape_glob(Customer.prefix)}#{delim}*#{delim}*"
Familia.dbclient.scan_each(match: pattern) { |key| ... }
```

## Only keys that hold a hash count

`all`, `keys_count`, `scan_count`, `keys_any?`, `scan_any?` and `scan_keys`,
and the SCAN-based `rebuild_instances`, `audit_instances` and SCAN fallback of
a `unique_index` rebuild, use only matching keys whose type is `hash`, the
type of an object key (`Familia::Horreum::OBJECT_KEY_TYPE`, `"hash"`). The
SCAN methods pass SCAN's `TYPE` option, and the KEYS methods check the type
of each key. README.md lists Valkey/Redis 6.0+ as a prerequisite, and that
does not change.

A key of another type whose name matches `customer:*:object`, such as the
bucket `customer:role_index:object` of a `multi_index` with a field value of
`object`, or a set an application wrote under the class prefix, used to be
counted, and loading it raised `Redis::WrongTypeError`:

```ruby
Familia.dbclient.sadd('customer:ghost:object', 'x')  # not an object

Customer.keys_count          # Before: 3 (two objects and the set)
                             # After:  2
Customer.keys_any?('ghost')  # Before: true    After: false
Customer.all                 # Before: raises Redis::WrongTypeError
                             # After:  the two objects
Customer.rebuild_instances   # Before: raises Redis::WrongTypeError
                             # After:  rebuilds from the two objects
```

The identifier glob of the counting methods is unchanged
(`Customer.keys_count('a*')`); the class prefix and suffix around it are now
escaped. Code that rescued `Redis::WrongTypeError` around `all` or
`rebuild_instances` for such keys can drop the rescue. Code that relied on
the counts to notice keys of other types has to look for them itself, for
example with `find_keys`.

## `rebuild_<index>` of a `multi_index` raises `Familia::IndexBucketConflictError`

The generated `rebuild_<index>` of a `multi_index`, such as
`Customer.rebuild_role_index` or `company.rebuild_dept_index`, deletes the
index's bucket sets and then writes one bucket per field value. It used to
SCAN `customer:role_index:*` and delete every match. A key under that prefix
that was not a bucket, such as the hash, list or set field of a customer whose
identifier is `role_index`, was deleted with the rest, and when a field value
named one of those fields, the rebuild wrote a bucket set in its place. The
scope identifier of an instance-scoped index went into the pattern unescaped,
so rebuilding a scope `c-*` deleted the buckets of `c-1` and `c-2` as well.
The literal part of the pattern is now escaped.

Before it deletes anything, the rebuild now checks every bucket key it will
write. It raises `Familia::IndexBucketConflictError`, a
`Familia::PersistenceError`, when one of them holds a type other than set, is
a set field or `multi_index` bucket of an existing record of the same class
with a longer identifier, or has more candidate owner records than
`Familia::Features::Relationships::Indexing::RecordKeyOwnership::MAX_CANDIDATE_SPLITS`
(8). It raises the same way for a stale bucket under the prefix with too many
candidate owners. Nothing is deleted or written. A set under the prefix that
belongs to another record is left in place by a successful rebuild too.

With `list :notes`, `set :tags` and `multi_index :role, :role_index` on
`Customer`, a customer whose identifier is `role_index` owns
`customer:role_index:notes` and `customer:role_index:tags`. When the stored
roles of other customers are `notes` and `tags`:

```ruby
# Before: deleted customer:role_index:object, :notes and :tags, then wrote
# :notes and :tags as bucket sets. The customer role_index was gone.

# After
begin
  Customer.rebuild_role_index
rescue Familia::IndexBucketConflictError => e
  e.conflicts
  # => {"customer:role_index:notes" => "list",
  #     "customer:role_index:tags" => "set"}
  e.owners
  # => {"customer:role_index:tags" => "customer:role_index:object"}
end
```

`conflicts` maps each key to the type it holds, or to
`:too_many_candidate_owners` for a key whose owner was not checked. `owners`
maps each key that belongs to another record to that record's hash key.
Inspect those keys, with `Familia.dbclient.type(key)` for the type and the
record named in `owners` for its field. The rebuild can run once none of them
holds a type other than set, belongs to another record or has too many
candidate owners. `audit_multi_indexes` lists the sets under the prefix that
the rebuild leaves alone in `foreign_owned_keys`. See
[Multi-value index rebuilds](../guides/feature-relationships-indexing.md#multi-value-index-rebuilds).

`repair_multi_indexes!` rescues the error. It records the index, or for an
instance-scoped index the scope, in `:skipped` and goes on with the next one.
It used to raise `Redis::WrongTypeError` when a key under the prefix held
another type:

```ruby
Customer.repair_multi_indexes!
# => {rebuilt: [], rebuilt_per_scope: [],
#     skipped: [{index_name: :role_index, reason: :bucket_conflict,
#                conflicts: {...}, owners: {...}}]}
```

The entry of an instance-scoped index also carries `scope_id:`. `repair_all!`
returns `status: :partial_failure` for such an entry, and its `errors` stays
`{}`:

```ruby
result = Customer.repair_all!
result[:status]                   # => :partial_failure
result[:errors]                   # => {}
result[:multi_indexes][:skipped]  # the entries above
```

Code that reads `errors` for the cause of a `:partial_failure` should also
read `result[:multi_indexes][:skipped]` for entries with
`reason: :bucket_conflict`.

The progress block of the rebuild gets a `:clearing` call with `key:` only
for a bucket its `DEL` removed, and `current:` counts those. It used to be
called for every SCAN match.

## `multi_index` methods and blank values

A blank field value is `nil`, or empty or whitespace only. The instance-scoped
`add_to_<scope>_<index>` and `update_in_<scope>_<index>` skipped `nil` but
added an object whose field value is empty or whitespace only to the key
`<index>_for` names for a blank value, `<scope key>:<index>` such as
`company:c-1:dept_index`, and the instance-scoped `find_all_by_<field>` and
`sample_from_<field>` returned that key's members for any blank value. Nothing
is now written for a blank value, as the class-level `add_to_class_<index>`
and `update_in_class_<index>` already did, and the finders return `[]`, as
the class-level `sample_from_<field>` already did. The class-level
`find_all_by_<field>` returned the members of `<class prefix>:<index>`, such
as `customer:role_index`, for a blank value, and now returns `[]` too. The
membership is still recorded, so `save` indexes the object once its value is
no longer blank.
`Familia::IndexDescriptor#each_record` raises `ArgumentError` for a blank
`value:` of a `multi_index`, as it already did for `nil`; it iterated that
key's members.

```ruby
employee = Employee.new(eid: 'e-1', department: '')
employee.save
employee.add_to_company_employees(company)
employee.add_to_company_dept_index(company)

company.find_all_by_department('')   # Before: [employee]   After: []
company.sample_from_department('')   # Before: [employee]   After: []

descriptor = Familia.multi_indexes(owner: Employee).first
descriptor.each_record(value: '', scope: company)
# Before: yielded employee    After: raises ArgumentError
```

Code that listed the objects without a value through
`find_all_by_<field>('')` can test the field on the participation collection
instead:

```ruby
company.employees.each_record.select { |e| e.department.to_s.strip.empty? }
```

Code that calls `each_record` with a value that may be blank should test the
value first or rescue `ArgumentError`.

Keys and related-field members that earlier versions wrote for blank values
stay in place after upgrading. Such a key is also the key of a related field
of the scope class with the index's name, and it can be a bucket of another
index, so the index methods leave it alone and this guide gives no cleanup.
The indexing guide's
[Blank field values](../guides/feature-relationships-indexing.md#blank-field-values)
section says how to inspect such a key and the members that a related field
of the same name may hold.

## `Familia::Migration::Model` defaults `@scan_pattern` to the model's `scan_pattern`

When `prepare` leaves `@scan_pattern` unset, it was set to
`"#{@model_class.prefix}:*:object"`, with a hardcoded `:` and `object` and no
escaping, and every matching key was passed to `load_from_key`. It is now set
to `@model_class.scan_pattern`, which follows `Familia.delim` and the class
suffix and escapes them and the prefix, and the new `scan_type` reader is set
to `Familia::Horreum::OBJECT_KEY_TYPE` (`"hash"`), the SCAN `TYPE` option, so
only object hashes reach `load_from_key`. `migrate` applies the default after
`prepare` has run; until then `scan_pattern` and `scan_type` return `nil`.
`Familia::Migration::Pipeline` scans the same way.

```ruby
class RoleMigration < Familia::Migration::Model
  def prepare
    @model_class = Customer   # @scan_pattern left unset
  end

  def process_record(obj, key)
    # the migration's work on each object
  end
end

migration = RoleMigration.new(run: true)
migration.prepare
migration.scan_pattern   # => nil, before and after
migration.migrate        # Before: false   After: true
# Before: the bucket customer:role_index:object was scanned, load_from_key
#         raised Redis::WrongTypeError on it, and error_count was 1
# After:  only the object hashes are processed, and error_count is 0
migration.scan_pattern   # => "customer:*:object", before and after
migration.scan_type      # After: "hash" (Before: NoMethodError)
```

A migration that sets `@scan_pattern` in `prepare` is unaffected: the pattern
is used as given and `scan_type` stays `nil`, so keys of every type are
scanned, unless `prepare` sets `@scan_type` as well. No change is needed for
the default. A model whose prefix, delimiter or suffix holds a glob character,
or whose delimiter is not `:` or suffix is not `object`, is now scanned by
its own keys; the old pattern did not match them.
