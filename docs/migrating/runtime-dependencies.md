# Upgrading from 2.12: runtime dependencies

The first release after 2.12.0 changes which gems familia declares and which
libraries `require 'familia'` loads. Each section below says what an
application has to change. Sections that do not apply to your application
need no action.

## `require 'familia'` no longer loads `base64`

familia 2.12.0 required `base64` when it loaded, so application code could
call `Base64` without requiring it. familia no longer requires `base64` or
depends on it. Code that relied on this raises
`NameError: uninitialized constant Base64` after the upgrade, on every Ruby
version, unless another library in the process happens to load `base64`.

Earlier versions of familia's documentation generated encryption keys like
this, with only `require 'familia'`:

```ruby
# Before
Familia.configure do |config|
  config.encryption_keys = {
    v1: Base64.strict_encode64(SecureRandom.bytes(32))
  }
end
```

`SecureRandom.base64(32)` generates the key without the `base64` gem:

```ruby
# After
require 'securerandom'

Familia.configure do |config|
  config.encryption_keys = {
    v1: SecureRandom.base64(32)
  }
end
```

To encode bytes you already have, such as fixed test keys, use
`[bytes].pack('m0')`. Both use the encoding `Base64.strict_encode64` uses,
because all three make the same core call: Ruby's
`Random::Formatter#base64`, which `SecureRandom.base64` uses, is
`[random_bytes(n)].pack("m0")`, and the `base64` gem's `strict_encode64` is
`[bin].pack("m0")`.

Code that keeps calling `Base64` must `require 'base64'` itself. Under
Bundler on Ruby 3.4 and later it must also list `base64` in the Gemfile,
because Ruby 3.4 moved `base64` out of the default gems. Ruby 3.4's
`bundled_gems.rb` lists it as `"base64" => "3.4.0"`.

## familia no longer depends on `connection_pool`

familia 2.12.0 declared `connection_pool` (`>= 2.4, < 4.0`) and required it
when it loaded. familia calls no `connection_pool` API, so it now does
neither, and it no longer limits which `connection_pool` version your
bundle resolves. Another gem in the bundle may still install and load
`connection_pool`, but nothing in familia ensures it.

An application that uses a `ConnectionPool` in `Familia.connection_provider`
should add the gem to its Gemfile and require it before building the pool:

```ruby
# Gemfile
gem 'connection_pool'
```

```ruby
require 'connection_pool'
```

The provider itself does not change. See "Connection Pooling" in the
[README](../../README.md#connection-pooling) for a complete provider.

## Minimum `oj` and `json_schemer` versions

`familia.gemspec` now requires `oj` `~> 3.16, >= 3.16.5` (was `~> 3.16`) and
`json_schemer` `~> 2.2` (was `~> 2.0`). A Gemfile or lockfile that pins an
older `oj` or `json_schemer` no longer resolves with familia. Raise or
remove the pin.

familia declares `json_schemer`, so an application needs no Gemfile entry
for it. If you keep one, it must allow 2.2 or later.

## Interactive migrations raise `PreconditionFailed`

A `Familia::Migration::Model` migration with `@interactive = true` loads
`pry-byebug` when `#migrate` starts. familia does not depend on
`pry-byebug`. When it is missing from the bundle or fails to load,
`#migrate` now raises `Familia::Migration::Errors::PreconditionFailed`
instead of `LoadError`, and `Familia::Migration::Runner` records the
migration as `:failed` instead of letting the `LoadError` end the run.

- To use interactive mode, add `pry-byebug` to the Gemfile, for example in
  the development group.
- Code that rescued `LoadError` around `#migrate` should rescue
  `Familia::Migration::Errors::PreconditionFailed` instead.

## Schema validation raises when `json_schemer` cannot load

When `json_schemer` is installed but one of its own requires fails, schema
validation now raises `Familia::SchemaValidatorLoadError`, whose `cause` is
the `LoadError`. familia 2.12.0 warned `json_schemer gem not installed` in
that case and disabled validation, so every record passed. With validation
hooks on, `Familia::Migration::Model#migrate` raises it at the first record
it validates instead of returning. `Familia::Migration::Base.run` and
`.cli_run` let it propagate rather than returning `false` or an exit code,
and `Familia::Migration::Runner` records the migration as `:failed`.

If you see this error, fix the bundle so that `json_schemer` loads. The
error's `cause` names the file that could not be loaded. When `json_schemer`
itself is absent, validation still warns and is disabled, as before.
